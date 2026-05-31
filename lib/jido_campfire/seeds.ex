defmodule Jido.Campfire.Seeds do
  @moduledoc """
  Demo workspace seed data and startup seeding for Campfire.

  The demo intentionally boots with one workspace, a few people, channels, DMs,
  and starter messages. Keeping those fixtures here makes `Jido.Campfire.Chat`
  a chat context instead of a mixed context/fixture module.
  """

  use GenServer

  alias Jido.Campfire.Chat.Mentions
  alias Jido.Campfire.Messaging

  @workspace_id "jido"
  @workspace_name "Jido Campfire"
  @current_user_id "user:you"
  @system_user_id "system:campfire"
  @default_room_id "room:general"

  @reaction_options [
    %{key: "+1", glyph: "👍", label: "Agree"},
    %{key: "ship", glyph: "🚀", label: "Ship"},
    %{key: "seen", glyph: "👀", label: "Seen"}
  ]

  @reaction_metadata Map.new(@reaction_options, fn option ->
                       {option.key, Map.take(option, [:glyph, :label])}
                     end)

  @people [
    %{
      id: "user:you",
      name: "You",
      handle: "you",
      initials: "YO",
      presence: :online,
      title: "Workspace owner",
      tone: "bg-[var(--campfire-accent)] text-stone-950"
    },
    %{
      id: "user:maggie",
      name: "Maggie",
      handle: "maggie",
      initials: "MH",
      presence: :online,
      title: "Adapter lead",
      tone: "bg-rose-200 text-rose-950"
    },
    %{
      id: "user:nolan",
      name: "Nolan",
      handle: "nolan",
      initials: "NO",
      presence: :online,
      title: "Runtime",
      tone: "bg-indigo-200 text-indigo-950"
    },
    %{
      id: "user:priya",
      name: "Priya",
      handle: "priya",
      initials: "PR",
      presence: :away,
      title: "Product design",
      tone: "bg-violet-200 text-violet-950"
    },
    %{
      id: "agent:alice",
      name: "Alice",
      handle: "alice",
      initials: "AL",
      presence: :online,
      title: "Architecture AI",
      type: :agent,
      capabilities: [:text, :ai],
      tone: "bg-cyan-200 text-cyan-950"
    },
    %{
      id: "agent:bob",
      name: "Bob",
      handle: "bob",
      initials: "BO",
      presence: :online,
      title: "Implementation AI",
      type: :agent,
      capabilities: [:text, :ai],
      tone: "bg-lime-200 text-lime-950"
    },
    %{
      id: "agent:charlie",
      name: "Charlie",
      handle: "charlie",
      initials: "CH",
      presence: :online,
      title: "Review AI",
      type: :agent,
      capabilities: [:text, :ai],
      tone: "bg-amber-200 text-amber-950"
    },
    %{
      id: @system_user_id,
      name: "Campfire",
      handle: "campfire",
      initials: "CF",
      presence: :online,
      title: "System",
      type: :system,
      tone: "bg-stone-800 text-stone-100"
    }
  ]

  @seed_channels [
    %{
      id: "room:general",
      name: "general",
      topic: "Daily coordination for the Jido messaging demo.",
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
      topic: "Messaging persistence, delivery, and Hologram state.",
      position: 30
    },
    %{
      id: "room:agent-lab",
      name: "agent-lab",
      topic: "Bounded Jido AI agent rounds with Alice, Bob, and Charlie.",
      position: 35,
      agent_room: true
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
    %{id: "dm:alice", participant_id: "agent:alice", position: 210},
    %{id: "dm:bob", participant_id: "agent:bob", position: 220},
    %{id: "dm:charlie", participant_id: "agent:charlie", position: 230}
  ]

  @seed_messages %{
    "room:general" => [
      {"user:maggie",
       "Campfire should prove the Hologram path without touching the existing UI package."},
      {"user:nolan", "SQLite is wired as a simple persistence layer behind jido_messaging."},
      {"user:priya",
       "The useful demo slice is channel switching, DMs, reactions, mentions, and threads."}
    ],
    "room:adapter-lab" => [
      {"user:maggie",
       "Slack outbound smoke is clean. Need a webhook replay before we call the adapter green."},
      {"user:priya", "I dropped the recent provider event shape in the lab thread."}
    ],
    "room:runtime" => [
      {"user:nolan",
       "Treat realtime as a notification layer, then read canonical records from jido_messaging."},
      {"user:maggie", "Persisted message IDs are the stable UI keys now."}
    ],
    "room:agent-lab" => [
      {"system:campfire",
       "Alice, Bob, and Charlie are Jido AI participants. Add ANTHROPIC_API_KEY, keep the safety cap on, and run a bounded agent round."},
      {"user:you",
       "Let's use this room to see how AI agents can participate in a normal Campfire channel."}
    ],
    "room:design" => [
      {"user:priya",
       "Keep the right panel contextual. Threads and room details can share that space."},
      {"user:you", "The sidebar should feel familiar, but Campfire can own the warmer accent."},
      {"user:maggie", "First screen is the chat workspace. No marketing shell."}
    ],
    "dm:maggie" => [
      {"user:maggie",
       "Can you keep the adapter lab and runtime work split? I want both paths visible."},
      {"user:you", "Yes. Channels for team rooms, DMs for person-to-person notes."}
    ],
    "dm:nolan" => [
      {"user:nolan", "SQLite durability is enough for the developer demo."}
    ],
    "dm:priya" => [
      {"user:priya", "Mobile needs a room switcher since the sidebar collapses."}
    ],
    "dm:alice" => [
      {"agent:alice",
       "Send me architecture questions from a room when you want a careful boundary pass."}
    ],
    "dm:bob" => [
      {"agent:bob", "I can turn a rough idea into a small implementation path."}
    ],
    "dm:charlie" => [
      {"agent:charlie", "I am useful when you want risk, test, and failure-mode review."}
    ]
  }

  def workspace_id, do: @workspace_id
  def workspace_name, do: @workspace_name
  def current_user_id, do: @current_user_id
  def system_user_id, do: @system_user_id
  def default_room_id, do: @default_room_id
  def people, do: @people
  def reaction_options, do: @reaction_options

  def agent_people do
    Enum.filter(@people, &(Map.get(&1, :type) == :agent))
  end

  def demo_users do
    @people
    |> Enum.reject(&Map.get(&1, :type))
    |> Enum.map(&person_view_from_seed/1)
  end

  def demo_user_ids do
    @people
    |> Enum.reject(&Map.get(&1, :type))
    |> Enum.map(& &1.id)
  end

  def person_seed(person_id) do
    Enum.find(@people, &(&1.id == person_id)) || fallback_person(person_id)
  end

  def reaction_metadata(emoji) do
    Map.get(@reaction_metadata, emoji, %{glyph: emoji, label: emoji})
  end

  def available_reaction_options(reactions) do
    reaction_keys = Enum.map(reactions, & &1.emoji)
    Enum.reject(@reaction_options, &(&1.key in reaction_keys))
  end

  def ensure_seeded! do
    seed_people()
    seed_rooms()
    seed_messages()
    :ok
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    ensure_seeded!()
    {:ok, %{}}
  end

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
                handle: person.handle,
                initials: person.initials,
                title: person.title,
                tone: person.tone
              },
              presence: person.presence,
              capabilities: Map.get(person, :capabilities, [:text])
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
          member_ids: channel_member_ids(channel),
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

  defp channel_member_ids(%{agent_room: true}),
    do: demo_user_ids() ++ Enum.map(agent_people(), & &1.id)

  defp channel_member_ids(_channel), do: demo_user_ids()

  defp message_role(@system_user_id), do: :system

  defp message_role(sender_id) do
    case person_seed(sender_id) do
      %{type: :agent} -> :assistant
      _person -> :user
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
                role: message_role(sender_id),
                content: [%{type: "text", text: text}],
                status: :sent,
                inserted_at: inserted_at,
                updated_at: inserted_at,
                metadata:
                  %{
                    workspace_id: @workspace_id,
                    source: "seed"
                  }
                  |> Map.merge(Mentions.metadata(text))
              })
          end)

        _other ->
          :ok
      end
    end)
  end

  defp person_view_from_seed(person) do
    %{
      id: person.id,
      name: person.name,
      handle: person.handle,
      initials: person.initials,
      title: person.title,
      tone: person.tone,
      presence: person.presence |> Atom.to_string()
    }
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
