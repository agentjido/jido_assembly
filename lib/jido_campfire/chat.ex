defmodule Jido.Campfire.Chat do
  @moduledoc """
  One-workspace chat context for the Campfire Hologram UI.

  This module owns only Campfire presentation choices: seeded workspace data,
  room/message view models, and Slack-like room creation. Canonical rooms,
  participants, and messages are stored through `Jido.Campfire.Messaging`.
  """

  alias Jido.Campfire.Messaging

  @workspace_id "jido"
  @workspace_name "Jido Campfire"
  @current_user_id "user:you"
  @default_room_id "room:general"

  @people [
    %{
      id: "user:you",
      name: "You",
      initials: "YO",
      presence: :online,
      title: "Workspace owner",
      tone: "bg-[var(--campfire-accent)] text-stone-950"
    },
    %{
      id: "user:maggie",
      name: "Maggie",
      initials: "MH",
      presence: :online,
      title: "Adapter lead",
      tone: "bg-rose-200 text-rose-950"
    },
    %{
      id: "user:nolan",
      name: "Nolan",
      initials: "NO",
      presence: :online,
      title: "Runtime",
      tone: "bg-indigo-200 text-indigo-950"
    },
    %{
      id: "user:priya",
      name: "Priya",
      initials: "PR",
      presence: :away,
      title: "Product design",
      tone: "bg-violet-200 text-violet-950"
    },
    %{
      id: "agent:room-assistant",
      name: "Room Assistant",
      initials: "RA",
      presence: :online,
      title: "Agent",
      type: :agent,
      tone: "bg-stone-800 text-stone-100"
    }
  ]

  @seed_channels [
    %{
      id: "room:general",
      name: "general",
      topic: "Daily coordination for Jido adapter work.",
      position: 10
    },
    %{
      id: "room:adapter-lab",
      name: "adapter-lab",
      topic: "Proof loops for bridges and provider events.",
      position: 20
    },
    %{
      id: "room:runtime",
      name: "runtime",
      topic: "Messaging persistence, delivery, and agent runtime.",
      position: 30
    },
    %{
      id: "room:design",
      name: "design",
      topic: "Campfire product surface and interaction model.",
      position: 40
    }
  ]

  @seed_dms [
    %{id: "dm:maggie", participant_id: "user:maggie", position: 110},
    %{id: "dm:nolan", participant_id: "user:nolan", position: 120},
    %{id: "dm:priya", participant_id: "user:priya", position: 130},
    %{id: "dm:room-assistant", participant_id: "agent:room-assistant", position: 140}
  ]

  @seed_messages %{
    "room:general" => [
      {"user:maggie",
       "Campfire should prove the Hologram path without touching the existing UI package."},
      {"user:nolan",
       "The useful slice is channel switching, a real composer, and a path for server commands."},
      {"user:priya",
       "I added room-context notes: bridge state on the right, channels on the left, timeline in the middle."},
      {"agent:room-assistant",
       "Campfire is now reading from jido_messaging. Hologram broadcasts update connected clients in realtime."}
    ],
    "room:adapter-lab" => [
      {"user:maggie",
       "Slack outbound smoke is clean. Need a webhook replay before we call the adapter green."},
      {"user:priya",
       "Telegram polling is connected. I dropped the recent event shape in the lab thread."},
      {"agent:room-assistant",
       "Next best check: normalize provider payloads into one table before adapter-specific UI polish."}
    ],
    "room:runtime" => [
      {"user:nolan",
       "I want the first Campfire persistence slice to read from jido_messaging without owning its schemas."},
      {"user:maggie",
       "Agree. Treat realtime as a notification layer, then re-read canonical messages after sends."},
      {"agent:room-assistant", "Persisted message IDs are the stable UI keys now."}
    ],
    "room:design" => [
      {"user:priya",
       "Keep the right panel contextual. Threads, bridge health, and agent suggestions can rotate through the same area."},
      {"user:you", "The sidebar should feel familiar, but Campfire can own the warmer accent."},
      {"user:maggie", "First screen is the chat workspace. No marketing shell."}
    ],
    "dm:maggie" => [
      {"user:maggie",
       "Can you keep the adapter lab and runtime work split? I want both paths visible."},
      {"user:you", "Yes. Channels for team rooms, DMs for person-to-person notes."}
    ],
    "dm:nolan" => [
      {"user:nolan", "The ETS adapter is fine for this spike. We can swap persistence later."}
    ],
    "dm:priya" => [
      {"user:priya", "Mobile needs a room switcher since the sidebar collapses."}
    ],
    "dm:room-assistant" => [
      {"agent:room-assistant",
       "I can summarize room context once the agent runner is wired into this shell."}
    ]
  }

  def workspace_id, do: @workspace_id
  def current_user_id, do: @current_user_id

  def current_user do
    person_view(@current_user_id)
  end

  def ensure_seeded! do
    seed_people()
    seed_rooms()
    seed_messages()
    :ok
  end

  def snapshot do
    ensure_seeded!()

    rooms = room_views()
    {channels, direct_messages} = split_rooms(rooms)
    active_room = Enum.find(rooms, &(&1.id == @default_room_id)) || List.first(rooms)
    messages_by_room = Map.new(rooms, &{&1.id, list_message_views(&1.id)})
    messages = Map.get(messages_by_room, active_room.id, [])

    %{
      workspace: %{id: @workspace_id, name: @workspace_name},
      current_user: current_user(),
      rooms: rooms,
      channels: channels,
      direct_messages: direct_messages,
      messages_by_room: messages_by_room,
      active_room: active_room,
      active_room_id: active_room.id,
      active_room_name: active_room.name,
      active_room_kind: active_room.kind,
      active_room_prefix: active_room.prefix,
      active_topic: active_room.topic,
      messages: messages,
      member_count_label: active_room.member_count_label
    }
  end

  def list_message_views(room_id) when is_binary(room_id) do
    ensure_seeded!()

    case Messaging.list_messages(room_id, limit: 100) do
      {:ok, messages} -> Enum.map(messages, &message_view/1)
      {:error, _reason} -> []
    end
  end

  def send_message(room_id, body, sender_id \\ @current_user_id) when is_binary(room_id) do
    ensure_seeded!()

    body = body |> to_string() |> String.trim()

    cond do
      body == "" ->
        {:error, :empty_message}

      true ->
        with {:ok, room} <- Messaging.get_room(room_id),
             {:ok, message} <-
               Messaging.save_message(%{
                 room_id: room.id,
                 sender_id: sender_id,
                 role: :user,
                 content: [%{type: "text", text: body}],
                 status: :sent,
                 metadata: %{
                   workspace_id: @workspace_id,
                   room_kind: room_kind(room),
                   source: "jido_campfire"
                 }
               }) do
          broadcast_messaging_event(room.id, {:message_added, message})
          {:ok, message_view(message)}
        end
    end
  end

  def create_channel(attrs) when is_map(attrs) do
    ensure_seeded!()

    name =
      attrs
      |> Map.get(:name, Map.get(attrs, "name", ""))
      |> normalize_channel_name()

    topic =
      attrs
      |> Map.get(:topic, Map.get(attrs, "topic", ""))
      |> to_string()
      |> String.trim()

    cond do
      name == "" ->
        {:error, :empty_name}

      true ->
        id = unique_room_id(name)
        position = System.system_time(:millisecond)

        with {:ok, room} <-
               Messaging.create_room(%{
                 id: id,
                 type: :channel,
                 name: name,
                 metadata: %{
                   workspace_id: @workspace_id,
                   campfire_kind: "channel",
                   topic: blank_to_default(topic, "Group chat for #{name}."),
                   member_ids: Enum.map(@people, & &1.id),
                   position: position
                 }
               }),
             {:ok, message} <-
               Messaging.save_message(%{
                 room_id: room.id,
                 sender_id: "agent:room-assistant",
                 role: :system,
                 content: [
                   %{
                     type: "text",
                     text: "Created ##{room.name}. Invite people by sharing this room."
                   }
                 ],
                 status: :sent,
                 metadata: %{workspace_id: @workspace_id, source: "jido_campfire"}
               }) do
          {:ok, room_view(room), [message_view(message)]}
        end
    end
  end

  def room_views do
    ensure_seeded!()

    case Messaging.list_rooms(limit: 500) do
      {:ok, rooms} ->
        rooms
        |> Enum.filter(&campfire_room?/1)
        |> Enum.sort_by(&room_sort_key/1)
        |> Enum.map(&room_view/1)

      {:error, _reason} ->
        []
    end
  end

  def room_view(room) do
    kind = room_kind(room)
    participant = if kind == "dm", do: dm_participant(room), else: nil
    name = if participant, do: participant.name, else: room.name
    topic = metadata_value(room.metadata, :topic, "No topic set.")
    member_ids = room_member_ids(room)

    %{
      id: room.id,
      name: name,
      kind: kind,
      prefix: if(kind == "dm", do: "@", else: "#"),
      topic: topic,
      unread: 0,
      online: participant && participant.presence == "online",
      presence: if(participant, do: participant.presence, else: "active"),
      avatar: if(participant, do: participant.initials, else: "#"),
      tone:
        if(participant, do: participant.tone, else: "bg-[var(--campfire-accent)] text-stone-950"),
      member_count: Enum.count(member_ids),
      member_count_label: member_count_label(kind, member_ids, participant),
      position: metadata_value(room.metadata, :position, 0)
    }
  end

  def message_view(message) do
    sender = person_view(message.sender_id)

    %{
      id: message.id,
      room_id: message.room_id,
      sender_id: message.sender_id,
      author: sender.name,
      avatar: sender.initials,
      tone: sender.tone,
      own: message.sender_id == @current_user_id,
      time: format_time(message.inserted_at),
      body: message_text(message),
      status: message.status |> Atom.to_string() |> String.replace("_", " ")
    }
  end

  def error_to_string(:empty_message), do: "Type a message first."
  def error_to_string(:empty_name), do: "Name the group chat first."
  def error_to_string(:not_found), do: "That room is no longer available."
  def error_to_string(reason), do: "Something went wrong: #{inspect(reason)}"

  defp seed_people do
    Enum.each(@people, fn person ->
      case Messaging.get_participant(person.id) do
        {:ok, _participant} ->
          :ok

        {:error, :not_found} ->
          {:ok, _participant} =
            Messaging.create_participant(%{
              id: person.id,
              type: Map.get(person, :type, :human),
              identity: %{
                name: person.name,
                initials: person.initials,
                title: person.title,
                tone: person.tone
              },
              presence: person.presence,
              capabilities: [:text]
            })

          :ok
      end
    end)
  end

  defp seed_rooms do
    Enum.each(@seed_channels, fn channel ->
      ensure_room(%{
        id: channel.id,
        type: :channel,
        name: channel.name,
        metadata: %{
          workspace_id: @workspace_id,
          campfire_kind: "channel",
          topic: channel.topic,
          member_ids: Enum.map(@people, & &1.id),
          position: channel.position
        }
      })
    end)

    Enum.each(@seed_dms, fn dm ->
      person = person_seed(dm.participant_id)

      ensure_room(%{
        id: dm.id,
        type: :direct,
        name: person.name,
        metadata: %{
          workspace_id: @workspace_id,
          campfire_kind: "dm",
          topic: "Direct messages with #{person.name}.",
          participant_ids: [@current_user_id, dm.participant_id],
          position: dm.position
        }
      })
    end)
  end

  defp ensure_room(attrs) do
    case Messaging.get_room(attrs.id) do
      {:ok, room} ->
        room

      {:error, :not_found} ->
        {:ok, room} = Messaging.create_room(attrs)
        room
    end
  end

  defp seed_messages do
    Enum.each(@seed_messages, fn {room_id, messages} ->
      case Messaging.list_messages(room_id, limit: 1) do
        {:ok, []} ->
          base = DateTime.add(DateTime.utc_now(), -3600, :second)

          messages
          |> Enum.with_index()
          |> Enum.each(fn {{sender_id, text}, index} ->
            inserted_at = DateTime.add(base, index * 180, :second)

            {:ok, _message} =
              Messaging.save_message(%{
                room_id: room_id,
                sender_id: sender_id,
                role: if(String.starts_with?(sender_id, "agent:"), do: :assistant, else: :user),
                content: [%{type: "text", text: text}],
                status: :sent,
                inserted_at: inserted_at,
                updated_at: inserted_at,
                metadata: %{workspace_id: @workspace_id, source: "seed"}
              })
          end)

        _other ->
          :ok
      end
    end)
  end

  defp broadcast_messaging_event(room_id, event) do
    _ = Jido.Messaging.PubSub.broadcast(Messaging, room_id, event)
    :ok
  end

  defp room_sort_key(room) do
    kind_weight = if room_kind(room) == "channel", do: 0, else: 1
    {kind_weight, metadata_value(room.metadata, :position, 0), room.name || ""}
  end

  defp split_rooms(rooms) do
    Enum.split_with(rooms, &(&1.kind == "channel"))
  end

  defp campfire_room?(room) do
    metadata_value(room.metadata, :workspace_id, nil) == @workspace_id
  end

  defp room_kind(room) do
    metadata_value(room.metadata, :campfire_kind, Atom.to_string(room.type))
  end

  defp room_member_ids(room) do
    metadata_value(
      room.metadata,
      :member_ids,
      metadata_value(room.metadata, :participant_ids, [])
    )
  end

  defp dm_participant(room) do
    room.metadata
    |> metadata_value(:participant_ids, [])
    |> Enum.reject(&(&1 == @current_user_id))
    |> List.first()
    |> person_view()
  end

  defp member_count_label("dm", _member_ids, %{presence: presence}), do: presence

  defp member_count_label(_kind, member_ids, _participant) do
    count = Enum.count(member_ids)
    "#{count} #{if count == 1, do: "member", else: "members"}"
  end

  defp person_view(nil), do: fallback_person("unknown")

  defp person_view(person_id) do
    case Messaging.get_participant(person_id) do
      {:ok, participant} ->
        identity = participant.identity || %{}

        %{
          id: participant.id,
          name: metadata_value(identity, :name, participant.id),
          initials:
            metadata_value(
              identity,
              :initials,
              initials_for(metadata_value(identity, :name, participant.id))
            ),
          title: metadata_value(identity, :title, ""),
          tone: metadata_value(identity, :tone, "bg-stone-200 text-stone-950"),
          presence: participant.presence |> Atom.to_string()
        }

      {:error, :not_found} ->
        fallback_person(person_id)
    end
  end

  defp person_seed(person_id) do
    Enum.find(@people, &(&1.id == person_id)) || fallback_person(person_id)
  end

  defp fallback_person(person_id) do
    %{
      id: person_id,
      name: person_id,
      initials: initials_for(person_id),
      title: "",
      tone: "bg-stone-200 text-stone-950",
      presence: "offline"
    }
  end

  defp metadata_value(nil, _key, default), do: default

  defp metadata_value(metadata, key, default) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key), default))
  end

  defp message_text(message) do
    message.content
    |> List.wrap()
    |> Enum.find_value("", fn
      %{type: "text", text: text} -> text
      %{type: :text, text: text} -> text
      %{"type" => "text", "text" => text} -> text
      text when is_binary(text) -> text
      _other -> nil
    end)
  end

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = inserted_at) do
    Calendar.strftime(inserted_at, "%H:%M")
  end

  defp normalize_channel_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp unique_room_id(name) do
    base = "room:#{name}"

    case Messaging.get_room(base) do
      {:error, :not_found} -> base
      {:ok, _room} -> "#{base}-#{System.unique_integer([:positive])}"
    end
  end

  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp initials_for(value) do
    value
    |> to_string()
    |> String.split(~r/[^a-zA-Z0-9]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
    |> case do
      "" -> "??"
      initials -> initials
    end
  end
end
