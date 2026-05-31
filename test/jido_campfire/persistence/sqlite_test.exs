defmodule Jido.Campfire.Persistence.SQLiteTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias Jido.Campfire.Persistence.SQLite
  alias Jido.Chat.{Participant, Room}
  alias Jido.Messaging.Message

  test "persists rooms, participants, and messages across adapter restarts" do
    path = Path.join(["tmp", "sqlite-test-#{System.unique_integer([:positive])}.sqlite3"])
    File.rm(path)

    {:ok, state} = SQLite.init(path: path)

    room =
      Room.new(%{
        id: "room:durable",
        type: :channel,
        name: "durable",
        metadata: %{workspace_id: "jido", campfire_kind: "channel"}
      })

    participant =
      Participant.new(%{
        id: "user:durable",
        type: :human,
        identity: %{name: "Durable User", initials: "DU"},
        presence: :online
      })

    message =
      Message.new(%{
        id: "message:durable",
        room_id: room.id,
        sender_id: participant.id,
        role: :user,
        content: [%{type: "text", text: "survives restart"}],
        status: :sent,
        metadata: %{workspace_id: "jido"}
      })

    assert {:ok, ^room} = SQLite.save_room(state, room)
    assert {:ok, ^participant} = SQLite.save_participant(state, participant)
    assert {:ok, ^message} = SQLite.save_message(state, message)
    :ok = Sqlite3.close(state.db)

    {:ok, restarted} = SQLite.init(path: path)

    assert {:ok, ^room} = SQLite.get_room(restarted, room.id)
    assert {:ok, ^participant} = SQLite.get_participant(restarted, participant.id)
    assert {:ok, [^message]} = SQLite.get_messages(restarted, room.id, limit: 10)

    :ok = Sqlite3.close(restarted.db)
  end

  test "does not cache messages when the SQLite write fails" do
    path = Path.join(["tmp", "sqlite-failed-write-#{System.unique_integer([:positive])}.sqlite3"])
    File.rm(path)

    {:ok, state} = SQLite.init(path: path)
    message = durable_message("message:failed-write")

    :ok = Sqlite3.close(state.db)

    assert {:error, _reason} = SQLite.save_message(state, message)
    assert {:error, :not_found} = SQLite.get_message(state, message.id)
  end

  test "keeps cached messages when the SQLite delete fails" do
    path =
      Path.join(["tmp", "sqlite-failed-delete-#{System.unique_integer([:positive])}.sqlite3"])

    File.rm(path)

    {:ok, state} = SQLite.init(path: path)
    message = durable_message("message:failed-delete")

    assert {:ok, ^message} = SQLite.save_message(state, message)
    :ok = Sqlite3.close(state.db)

    assert {:error, _reason} = SQLite.delete_message(state, message.id)
    assert {:ok, ^message} = SQLite.get_message(state, message.id)
  end

  defp durable_message(id) do
    Message.new(%{
      id: id,
      room_id: "room:durable",
      sender_id: "user:durable",
      role: :user,
      content: [%{type: "text", text: "durable message"}],
      status: :sent,
      metadata: %{workspace_id: "jido"}
    })
  end
end
