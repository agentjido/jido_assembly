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
end
