defmodule Jido.Campfire.ChatTest do
  use ExUnit.Case, async: false

  alias Jido.Campfire.Chat

  test "snapshot exposes one workspace with group chats and DMs" do
    snapshot = Chat.snapshot()

    assert snapshot.workspace.name == "Jido Campfire"
    assert Enum.any?(snapshot.channels, &(&1.id == "room:general"))
    assert Enum.any?(snapshot.direct_messages, &(&1.id == "dm:maggie"))
    assert Map.has_key?(snapshot.messages_by_room, snapshot.active_room_id)
  end

  test "snapshot exposes the developer showcase stack" do
    showcase = Chat.snapshot().developer_showcase

    stack_names = Enum.map(showcase.stack, & &1.name)
    assert "Hologram" in stack_names
    assert "Jido Messaging" in stack_names
    assert "Jido Chat" in stack_names
    assert "Jido" in stack_names

    assert Enum.any?(showcase.chat_contract, &(&1.detail == "Jido.Chat.MessagingTarget"))
    assert Enum.any?(showcase.capabilities, &(&1.feature == "Threads"))
  end

  test "send_message persists through jido_messaging" do
    body = "test message #{System.unique_integer([:positive])}"

    assert {:ok, message} = Chat.send_message("room:general", body)
    assert message.body == body
    assert message.own

    assert Enum.any?(Chat.list_message_views("room:general"), &(&1.id == message.id))
  end

  test "create_channel creates a new group chat with an initial system message" do
    name = "spike-#{System.unique_integer([:positive])}"

    assert {:ok, room, [message]} = Chat.create_channel(%{name: name, topic: "Test room"})
    assert room.kind == "channel"
    assert room.name == name
    assert message.room_id == room.id
    assert Enum.any?(Chat.room_views(), &(&1.id == room.id))
  end

  test "send_message supports demo users and mention metadata" do
    body = "@priya can you look at this? #{System.unique_integer([:positive])}"

    assert {:ok, message} = Chat.send_message("room:general", body, "user:maggie")
    assert message.sender_id == "user:maggie"
    assert message.author == "Maggie"
    assert "user:priya" in message.mentioned_user_ids
  end

  test "toggle_reaction persists reaction state on messages" do
    body = "reaction target #{System.unique_integer([:positive])}"
    assert {:ok, message} = Chat.send_message("room:general", body)

    assert {:ok, reacted} = Chat.toggle_reaction(message.id, "+1", "user:maggie")
    assert [%{emoji: "+1", count: 1, user_ids: ["user:maggie"]}] = reacted.reactions

    assert {:ok, unreacted} = Chat.toggle_reaction(message.id, "+1", "user:maggie")
    assert unreacted.reactions == []
  end

  test "thread replies are listed under the root message" do
    root_body = "thread root #{System.unique_integer([:positive])}"
    assert {:ok, root} = Chat.send_message("room:general", root_body)

    assert {:ok, reply} =
             Chat.send_message("room:general", "reply body", "user:nolan",
               thread_id: root.id,
               reply_to_id: root.id
             )

    refute Enum.any?(Chat.list_message_views("room:general"), &(&1.id == reply.id))

    assert [%{id: reply_id}] = Chat.list_thread_views("room:general", root.id)
    assert reply_id == reply.id

    assert %{reply_count: 1} =
             Chat.list_message_views("room:general")
             |> Enum.find(&(&1.id == root.id))
  end

  test "search returns matching messages across the workspace" do
    unique = "needle-#{System.unique_integer([:positive])}"
    assert {:ok, message} = Chat.send_message("room:runtime", unique, "user:priya")

    assert [%{message_id: message_id, room_id: "room:runtime"} | _] = Chat.search(unique)
    assert message_id == message.id
  end
end
