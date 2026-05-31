defmodule Jido.Campfire.DeveloperShowcase do
  @moduledoc """
  Developer-facing metadata for the Campfire demo.

  This module keeps the product UI honest about what the demo is proving. The
  running chat path is Hologram over `jido_messaging` with a SQLite persistence
  adapter. `jido_chat` is represented by the canonical chat types and adapter
  contract vocabulary that `jido_messaging` builds on.
  """

  alias Jido.Chat.{MessagingTarget, PostPayload}

  @workspace_id "jido"

  def snapshot(active_room, messages, threads_by_root, rooms) do
    %{
      stack: stack_layers(),
      capabilities: capability_rows(),
      contracts_by_room: contracts_by_room(rooms),
      chat_contract: chat_contract(active_room),
      room_metrics:
        room_metrics(active_room, Enum.count(messages), map_size(threads_by_root || %{})),
      last_event: event("Workspace loaded", "Hologram init", room_label(active_room))
    }
  end

  def stack_layers do
    [
      %{
        name: "Hologram",
        badge: "UI",
        role: "Client actions, server commands, and realtime broadcasts."
      },
      %{
        name: "Jido Messaging",
        badge: "runtime",
        role: "Canonical rooms, messages, thread records, reactions, and PubSub events."
      },
      %{
        name: "SQLite",
        badge: "durable",
        role: "Small local persistence adapter backing the demo process."
      },
      %{
        name: "Jido Chat",
        badge: "contract",
        role: "Typed chat handles and payload vocabulary for adapter-facing work."
      },
      %{
        name: "Jido",
        badge: "later",
        role: "Native agent showcase is intentionally left for the next slice."
      }
    ]
  end

  def capability_rows do
    [
      %{feature: "Channels", status: "implemented", detail: "Group rooms in jido_messaging."},
      %{feature: "DMs", status: "implemented", detail: "Direct rooms with demo participants."},
      %{feature: "Threads", status: "implemented", detail: "Root message plus reply records."},
      %{feature: "Reactions", status: "implemented", detail: "Stored on message reaction maps."},
      %{feature: "Search", status: "implemented", detail: "Simple workspace scan for the demo."},
      %{feature: "Jido agents", status: "deferred", detail: "Kept out of this UI slice."}
    ]
  end

  def contracts_by_room(rooms) do
    Map.new(rooms, fn room -> {room.id, chat_contract(room)} end)
  end

  def chat_contract(room) do
    target =
      MessagingTarget.for_room(room.id,
        kind: target_kind(room),
        channel_type: :campfire,
        instance_id: @workspace_id
      )

    payload =
      PostPayload.text("Message #{room_label(room)}",
        metadata: %{workspace_id: @workspace_id, room_id: room.id, source: "jido_campfire"}
      )

    [
      %{
        label: "Target",
        value: "#{target.kind} #{target.external_id}",
        detail: "Jido.Chat.MessagingTarget"
      },
      %{
        label: "Payload",
        value: Atom.to_string(payload.kind),
        detail: "Jido.Chat.PostPayload"
      },
      %{
        label: "Write path",
        value: "save_message",
        detail: "Jido.Campfire.Messaging to jido_messaging"
      }
    ]
  end

  def room_metrics(room, message_count, thread_count) do
    [
      %{label: "Room", value: room_label(room)},
      %{label: "Type", value: room.kind},
      %{label: "Messages", value: Integer.to_string(message_count)},
      %{label: "Threads", value: Integer.to_string(thread_count)},
      %{label: "Durability", value: "SQLite"}
    ]
  end

  def event(title, layer, detail) do
    %{
      title: title,
      layer: layer,
      detail: detail
    }
  end

  defp target_kind(%{kind: "dm"}), do: :dm
  defp target_kind(_room), do: :room

  defp room_label(room), do: "#{room.prefix}#{room.name}"
end
