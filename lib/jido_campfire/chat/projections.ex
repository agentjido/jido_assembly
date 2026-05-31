defmodule Jido.Campfire.Chat.Projections do
  @moduledoc """
  Read-model projections for Campfire chat records.

  `Jido.Campfire.Chat` owns the public context API and write operations. This
  module reads canonical `Jido.Campfire.Messaging` records and turns them into
  the room, message, person, reaction, and search maps consumed by Hologram.
  """

  alias Jido.Campfire.{Messaging, Seeds}

  def room_views(presence \\ %{online_user_ids: []}) do
    case Messaging.list_rooms(limit: 500) do
      {:ok, rooms} ->
        rooms
        |> Enum.filter(&campfire_room?/1)
        |> Enum.sort_by(&room_sort_key/1)
        |> Enum.map(&room_view(&1, presence))

      {:error, _reason} ->
        []
    end
  end

  def room_view(room, presence \\ %{online_user_ids: []}) do
    kind = room_kind(room)
    participant = if kind == "dm", do: dm_participant(room, presence), else: nil
    participant_id = participant && participant.id
    availability = if participant, do: participant.availability, else: "active"
    online = participant_id && online?(presence, participant_id)
    presence = if participant, do: if(online, do: availability, else: "offline"), else: "active"
    name = if participant, do: participant.name, else: room.name
    topic = metadata_value(room.metadata, :topic, "No topic set.")
    member_ids = room_member_ids(room)

    %{
      id: room.id,
      name: name,
      kind: kind,
      participant_id: participant_id,
      prefix: if(kind == "dm", do: "@", else: "#"),
      topic: topic,
      unread: 0,
      mention_unread: 0,
      online: online,
      presence: presence,
      availability: availability,
      avatar: if(participant, do: participant.initials, else: "#"),
      tone:
        if(participant, do: participant.tone, else: "bg-[var(--campfire-accent)] text-stone-950"),
      member_count: Enum.count(member_ids),
      member_count_label: member_count_label(kind, member_ids, presence),
      position: metadata_value(room.metadata, :position, 0)
    }
  end

  def split_rooms(rooms) do
    Enum.split_with(rooms, &(&1.kind == "channel"))
  end

  def room_message_data(room_id, user_id, presence \\ %{online_user_ids: []}) do
    case Messaging.room_timeline(room_id, limit: 500) do
      {:ok, %{messages: messages, threads: replies_by_thread, reply_counts: reply_counts}} ->
        timeline =
          messages
          |> Enum.map(fn message ->
            reply_count = Map.get(reply_counts, message.id, 0)
            message_view(message, user_id, reply_count, presence)
          end)

        threads =
          Map.new(replies_by_thread, fn {thread_id, replies} ->
            {thread_id, Enum.map(replies, &message_view(&1, user_id, 0, presence))}
          end)

        {timeline, threads}

      {:error, _reason} ->
        {[], %{}}
    end
  end

  def list_message_views(room_id, user_id, presence \\ %{online_user_ids: []}) do
    {messages, _threads} = room_message_data(room_id, user_id, presence)
    messages
  end

  def list_thread_views(room_id, root_message_id, user_id, presence \\ %{online_user_ids: []}) do
    {_messages, threads} = room_message_data(room_id, user_id, presence)
    Map.get(threads, root_message_id, [])
  end

  def message_view_with_reply_count(message, user_id, presence \\ %{online_user_ids: []})

  def message_view_with_reply_count(%{thread_id: thread_id} = message, user_id, presence)
      when is_binary(thread_id) do
    message_view(message, user_id, 0, presence)
  end

  def message_view_with_reply_count(message, user_id, presence) do
    reply_count =
      case Messaging.room_timeline(message.room_id, limit: 500) do
        {:ok, %{reply_counts: reply_counts}} -> Map.get(reply_counts, message.id, 0)
        {:error, _reason} -> 0
      end

    message_view(message, user_id, reply_count, presence)
  end

  def message_view(message, user_id, reply_count \\ 0, presence \\ %{online_user_ids: []}) do
    sender = person(message.sender_id, presence)
    mentioned_user_ids = metadata_value(message.metadata, :mentions, [])
    reactions = reaction_views(message.reactions || %{}, user_id)

    %{
      id: message.id,
      room_id: message.room_id,
      sender_id: message.sender_id,
      author: sender.name,
      avatar: sender.initials,
      tone: sender.tone,
      own: message.sender_id == user_id,
      time: format_time(message.inserted_at),
      body: message_text(message),
      status: message.status |> Atom.to_string() |> String.replace("_", " "),
      thread_id: message.thread_id,
      reply_to_id: message.reply_to_id,
      is_reply: is_binary(message.thread_id),
      reply_count: reply_count,
      mentioned_user_ids: mentioned_user_ids,
      mentions_current_user: user_id in mentioned_user_ids,
      reactions: reactions,
      available_reactions: Seeds.available_reaction_options(reactions)
    }
  end

  def person(person_id, presence \\ %{online_user_ids: []})

  def person(nil, _presence), do: fallback_person("unknown")

  def person(person_id, presence) do
    case Messaging.get_participant(person_id) do
      {:ok, participant} ->
        identity = participant.identity || %{}
        availability = participant.presence |> Atom.to_string()
        online = online?(presence, participant.id)

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
          availability: availability,
          online: online,
          presence: if(online, do: availability, else: "offline")
        }

      {:error, :not_found} ->
        fallback_person(person_id)
    end
  end

  def room_kind(room) do
    metadata_value(room.metadata, :campfire_kind, Atom.to_string(room.type))
  end

  def search(query, user_id, presence \\ %{online_user_ids: []}) do
    query = query |> to_string() |> String.trim() |> String.downcase()

    if query == "" do
      []
    else
      room_views(presence)
      |> Enum.flat_map(fn room ->
        room.id
        |> list_all_message_views(user_id, presence)
        |> Enum.filter(&search_match?(&1, query, room))
        |> Enum.map(&search_result(room, &1))
      end)
      |> Enum.take(20)
    end
  end

  def metadata_value(nil, _key, default), do: default

  def metadata_value(metadata, key, default) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key), default))
  end

  defp list_all_message_views(room_id, user_id, presence) do
    {timeline, threads} = room_message_data(room_id, user_id, presence)
    timeline ++ (threads |> Map.values() |> List.flatten())
  end

  defp reaction_views(reactions, user_id) do
    reactions
    |> Enum.map(fn {emoji, user_ids} ->
      user_ids = List.wrap(user_ids)
      metadata = Seeds.reaction_metadata(emoji)

      %{
        emoji: emoji,
        glyph: metadata.glyph,
        label: metadata.label,
        count: Enum.count(user_ids),
        reacted: user_id in user_ids,
        user_ids: user_ids
      }
    end)
    |> Enum.sort_by(& &1.emoji)
  end

  defp search_match?(message, query, room) do
    values = [message.body, message.author, room.name]

    Enum.any?(values, fn value ->
      value |> to_string() |> String.downcase() |> String.contains?(query)
    end)
  end

  defp search_result(room, message) do
    %{
      room_id: room.id,
      room_label: "#{room.prefix}#{room.name}",
      message_id: message.id,
      thread_id: message.thread_id,
      author: message.author,
      body: message.body,
      time: message.time
    }
  end

  defp room_sort_key(room) do
    kind_weight = if room_kind(room) == "channel", do: 0, else: 1
    {kind_weight, metadata_value(room.metadata, :position, 0), room.name || ""}
  end

  defp campfire_room?(room) do
    metadata_value(room.metadata, :workspace_id, nil) == Seeds.workspace_id()
  end

  defp room_member_ids(room) do
    metadata_value(
      room.metadata,
      :member_ids,
      metadata_value(room.metadata, :participant_ids, [])
    )
  end

  defp dm_participant(room, presence) do
    room.metadata
    |> metadata_value(:participant_ids, [])
    |> Enum.reject(&(&1 == Seeds.current_user_id()))
    |> List.first()
    |> person(presence)
  end

  defp member_count_label("dm", _member_ids, presence), do: presence

  defp member_count_label(_kind, member_ids, _presence) do
    count = Enum.count(member_ids)
    "#{count} #{if count == 1, do: "member", else: "members"}"
  end

  defp online?(%{online_user_ids: online_user_ids}, participant_id) do
    participant_id in online_user_ids
  end

  defp online?(_presence, _participant_id), do: false

  defp fallback_person(person_id) do
    %{
      id: person_id,
      name: person_id,
      initials: initials_for(person_id),
      title: "",
      tone: "bg-stone-200 text-stone-950",
      availability: "offline",
      online: false,
      presence: "offline"
    }
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
