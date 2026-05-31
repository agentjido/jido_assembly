defmodule Jido.Campfire.Persistence.SQLite do
  @moduledoc """
  Tiny durable persistence adapter for the Campfire developer demo.

  The adapter keeps `jido_messaging`'s ETS adapter as the query/index layer and
  mirrors durable records into SQLite. On boot it reloads SQLite records back
  into ETS. This is intentionally simple: it gives the demo restart-safe rooms,
  participants, threads, messages, reactions, and bindings without introducing
  an Ecto schema surface.
  """

  @behaviour Jido.Messaging.Persistence
  @behaviour Jido.Messaging.Directory

  alias Exqlite.Sqlite3
  alias Jido.Messaging.Persistence.ETS
  alias Jido.Messaging.{IngressSubscription, Message, RoomBinding, Thread}

  @core_kinds ["participant", "room", "thread", "message", "room_binding"]
  @control_kinds ["onboarding", "bridge_config", "ingress_subscription", "routing_policy"]

  defstruct [:db, :ets, :path]

  @impl true
  def init(opts) do
    path = opts |> Keyword.get(:path, "data/jido_campfire.sqlite3") |> to_string()
    :ok = ensure_parent_dir(path)

    with {:ok, db} <- Sqlite3.open(path),
         :ok <- migrate(db),
         {:ok, ets} <- ETS.init([]) do
      state = %__MODULE__{db: db, ets: ets, path: path}
      {:ok, load_records(state)}
    end
  end

  @impl true
  def save_room(state, room) do
    with {:ok, room} <- ETS.save_room(state.ets, room),
         :ok <- upsert_record(state, "room", room.id, room, room_id: room.id) do
      {:ok, room}
    end
  end

  @impl true
  def get_room(state, room_id), do: ETS.get_room(state.ets, room_id)

  @impl true
  def delete_room(state, room_id) do
    with :ok <- ETS.delete_room(state.ets, room_id),
         :ok <- delete_room_records(state, room_id) do
      :ok
    end
  end

  @impl true
  def list_rooms(state, opts \\ []), do: ETS.list_rooms(state.ets, opts)

  @impl true
  def save_participant(state, participant) do
    with {:ok, participant} <- ETS.save_participant(state.ets, participant),
         :ok <- upsert_record(state, "participant", participant.id, participant) do
      {:ok, participant}
    end
  end

  @impl true
  def get_participant(state, participant_id), do: ETS.get_participant(state.ets, participant_id)

  @impl true
  def delete_participant(state, participant_id) do
    with :ok <- ETS.delete_participant(state.ets, participant_id),
         :ok <- delete_record(state, "participant", participant_id) do
      :ok
    end
  end

  @impl true
  def save_message(state, %Message{} = message) do
    with {:ok, message} <- ETS.save_message(state.ets, message),
         :ok <-
           upsert_record(state, "message", message.id, message,
             room_id: message.room_id,
             thread_id: message.thread_id,
             inserted_at: message.inserted_at
           ) do
      {:ok, message}
    end
  end

  @impl true
  def get_message(state, message_id), do: ETS.get_message(state.ets, message_id)

  @impl true
  def get_messages(state, room_id, opts \\ []), do: ETS.get_messages(state.ets, room_id, opts)

  @impl true
  def delete_message(state, message_id) do
    with :ok <- ETS.delete_message(state.ets, message_id),
         :ok <- delete_record(state, "message", message_id) do
      :ok
    end
  end

  @impl true
  def save_thread(state, %Thread{} = thread) do
    with {:ok, thread} <- ETS.save_thread(state.ets, thread),
         :ok <-
           upsert_record(state, "thread", thread.id, thread,
             room_id: thread.room_id,
             inserted_at: thread.inserted_at
           ) do
      {:ok, thread}
    end
  end

  @impl true
  def get_thread(state, thread_id), do: ETS.get_thread(state.ets, thread_id)

  @impl true
  def get_thread_by_external_id(state, room_id, external_thread_id) do
    ETS.get_thread_by_external_id(state.ets, room_id, external_thread_id)
  end

  @impl true
  def get_thread_by_root_message(state, room_id, root_message_id) do
    ETS.get_thread_by_root_message(state.ets, room_id, root_message_id)
  end

  @impl true
  def list_threads(state, room_id, opts \\ []), do: ETS.list_threads(state.ets, room_id, opts)

  @impl true
  def get_or_create_room_by_external_binding(state, channel, bridge_id, external_id, attrs) do
    with {:ok, room} <-
           ETS.get_or_create_room_by_external_binding(
             state.ets,
             channel,
             bridge_id,
             external_id,
             attrs
           ),
         :ok <- upsert_record(state, "room", room.id, room, room_id: room.id) do
      {:ok, room}
    end
  end

  @impl true
  def get_or_create_participant_by_external_id(state, channel, external_id, attrs) do
    with {:ok, participant} <-
           ETS.get_or_create_participant_by_external_id(state.ets, channel, external_id, attrs),
         :ok <- upsert_record(state, "participant", participant.id, participant) do
      {:ok, participant}
    end
  end

  @impl true
  def get_message_by_external_id(state, channel, bridge_id, external_id) do
    ETS.get_message_by_external_id(state.ets, channel, bridge_id, external_id)
  end

  @impl true
  def update_message_external_id(state, message_id, external_id) do
    with {:ok, message} <- ETS.update_message_external_id(state.ets, message_id, external_id),
         :ok <-
           upsert_record(state, "message", message.id, message,
             room_id: message.room_id,
             thread_id: message.thread_id,
             inserted_at: message.inserted_at
           ) do
      {:ok, message}
    end
  end

  @impl true
  def get_room_by_external_binding(state, channel, bridge_id, external_id) do
    ETS.get_room_by_external_binding(state.ets, channel, bridge_id, external_id)
  end

  @impl true
  def create_room_binding(state, room_id, channel, bridge_id, external_id, attrs) do
    with {:ok, %RoomBinding{} = binding} <-
           ETS.create_room_binding(state.ets, room_id, channel, bridge_id, external_id, attrs),
         :ok <- upsert_record(state, "room_binding", binding.id, binding, room_id: room_id) do
      {:ok, binding}
    end
  end

  @impl true
  def list_room_bindings(state, room_id), do: ETS.list_room_bindings(state.ets, room_id)

  @impl true
  def delete_room_binding(state, binding_id) do
    with :ok <- ETS.delete_room_binding(state.ets, binding_id),
         :ok <- delete_record(state, "room_binding", binding_id) do
      :ok
    end
  end

  @impl Jido.Messaging.Directory
  def lookup(state, target, query), do: directory_lookup(state, target, query, [])

  @impl Jido.Messaging.Directory
  def search(state, target, query), do: directory_search(state, target, query, [])

  @impl true
  def directory_lookup(state, target, query, opts \\ []) do
    ETS.directory_lookup(state.ets, target, query, opts)
  end

  @impl true
  def directory_search(state, target, query, opts \\ []) do
    ETS.directory_search(state.ets, target, query, opts)
  end

  @impl true
  def save_onboarding(state, onboarding_flow) do
    onboarding_id =
      Map.get(onboarding_flow, :onboarding_id) || Map.get(onboarding_flow, "onboarding_id")

    with {:ok, onboarding_flow} <- ETS.save_onboarding(state.ets, onboarding_flow),
         :ok <- upsert_record(state, "onboarding", onboarding_id, onboarding_flow) do
      {:ok, onboarding_flow}
    end
  end

  @impl true
  def get_onboarding(state, onboarding_id), do: ETS.get_onboarding(state.ets, onboarding_id)

  @impl true
  def save_bridge_config(state, bridge_config) do
    with {:ok, bridge_config} <- ETS.save_bridge_config(state.ets, bridge_config),
         :ok <- upsert_record(state, "bridge_config", bridge_config.id, bridge_config) do
      {:ok, bridge_config}
    end
  end

  @impl true
  def get_bridge_config(state, bridge_id), do: ETS.get_bridge_config(state.ets, bridge_id)

  @impl true
  def list_bridge_configs(state, opts \\ []), do: ETS.list_bridge_configs(state.ets, opts)

  @impl true
  def delete_bridge_config(state, bridge_id) do
    with :ok <- ETS.delete_bridge_config(state.ets, bridge_id),
         :ok <- delete_record(state, "bridge_config", bridge_id) do
      :ok
    end
  end

  @impl true
  def save_ingress_subscription(state, %IngressSubscription{} = subscription) do
    id = "#{subscription.bridge_id}:#{subscription.subscription_id}"

    with {:ok, subscription} <- ETS.save_ingress_subscription(state.ets, subscription),
         :ok <-
           upsert_record(state, "ingress_subscription", id, subscription,
             room_id: subscription.bridge_id
           ) do
      {:ok, subscription}
    end
  end

  @impl true
  def list_ingress_subscriptions(state, bridge_id, opts \\ []) do
    ETS.list_ingress_subscriptions(state.ets, bridge_id, opts)
  end

  @impl true
  def delete_ingress_subscription(state, bridge_id, subscription_id) do
    with :ok <- ETS.delete_ingress_subscription(state.ets, bridge_id, subscription_id),
         :ok <- delete_record(state, "ingress_subscription", "#{bridge_id}:#{subscription_id}") do
      :ok
    end
  end

  @impl true
  def save_routing_policy(state, routing_policy) do
    with {:ok, routing_policy} <- ETS.save_routing_policy(state.ets, routing_policy),
         :ok <-
           upsert_record(state, "routing_policy", routing_policy.room_id, routing_policy,
             room_id: routing_policy.room_id
           ) do
      {:ok, routing_policy}
    end
  end

  @impl true
  def get_routing_policy(state, room_id), do: ETS.get_routing_policy(state.ets, room_id)

  @impl true
  def delete_routing_policy(state, room_id) do
    with :ok <- ETS.delete_routing_policy(state.ets, room_id),
         :ok <- delete_record(state, "routing_policy", room_id) do
      :ok
    end
  end

  defp ensure_parent_dir(":memory:"), do: :ok

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp migrate(db) do
    exec(db, """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;

    CREATE TABLE IF NOT EXISTS campfire_records (
      kind TEXT NOT NULL,
      id TEXT NOT NULL,
      room_id TEXT,
      thread_id TEXT,
      inserted_at TEXT,
      payload BLOB NOT NULL,
      PRIMARY KEY (kind, id)
    );

    CREATE INDEX IF NOT EXISTS campfire_records_room_idx
      ON campfire_records (kind, room_id);

    CREATE INDEX IF NOT EXISTS campfire_records_thread_idx
      ON campfire_records (kind, thread_id);
    """)
  end

  defp load_records(state) do
    records =
      query_all(
        state.db,
        """
        SELECT kind, id, room_id, thread_id, inserted_at, payload
        FROM campfire_records
        ORDER BY inserted_at ASC, id ASC
        """
      )
      |> Enum.map(fn [kind, _id, _room_id, _thread_id, _inserted_at, payload] ->
        {kind, :erlang.binary_to_term(payload)}
      end)

    Enum.each(@core_kinds ++ @control_kinds, fn kind ->
      records
      |> Enum.filter(fn {record_kind, _record} -> record_kind == kind end)
      |> Enum.each(fn {_record_kind, record} -> restore_record(state.ets, kind, record) end)
    end)

    state
  end

  defp restore_record(ets, "participant", record), do: ETS.save_participant(ets, record)
  defp restore_record(ets, "room", record), do: ETS.save_room(ets, record)
  defp restore_record(ets, "thread", record), do: ETS.save_thread(ets, record)
  defp restore_record(ets, "message", record), do: ETS.save_message(ets, record)
  defp restore_record(ets, "onboarding", record), do: ETS.save_onboarding(ets, record)
  defp restore_record(ets, "bridge_config", record), do: ETS.save_bridge_config(ets, record)

  defp restore_record(ets, "ingress_subscription", record),
    do: ETS.save_ingress_subscription(ets, record)

  defp restore_record(ets, "routing_policy", record), do: ETS.save_routing_policy(ets, record)

  defp restore_record(ets, "room_binding", %RoomBinding{} = binding) do
    key = {binding.channel, to_string(binding.bridge_id), to_string(binding.external_room_id)}

    true = :ets.insert(ets.room_bindings, {key, binding.room_id})
    true = :ets.insert(ets.room_bindings_by_id, {binding.id, binding})
    true = :ets.insert(ets.room_bindings_by_room, {binding.room_id, binding.id})

    {:ok, binding}
  end

  defp upsert_record(state, kind, id, record, opts \\ []) do
    sql = """
    INSERT INTO campfire_records (kind, id, room_id, thread_id, inserted_at, payload)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    ON CONFLICT(kind, id) DO UPDATE SET
      room_id = excluded.room_id,
      thread_id = excluded.thread_id,
      inserted_at = excluded.inserted_at,
      payload = excluded.payload
    """

    run(
      state.db,
      sql,
      [
        kind,
        id,
        Keyword.get(opts, :room_id),
        Keyword.get(opts, :thread_id),
        format_datetime(Keyword.get(opts, :inserted_at)),
        {:blob, :erlang.term_to_binary(record)}
      ]
    )
  end

  defp delete_record(state, kind, id) do
    run(state.db, "DELETE FROM campfire_records WHERE kind = ?1 AND id = ?2", [kind, id])
  end

  defp delete_room_records(state, room_id) do
    run(
      state.db,
      """
      DELETE FROM campfire_records
      WHERE (kind = 'room' AND id = ?1)
         OR (kind IN ('message', 'thread', 'room_binding', 'routing_policy') AND room_id = ?1)
      """,
      [room_id]
    )
  end

  defp exec(db, sql) do
    case Sqlite3.execute(db, sql) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run(db, sql, params) do
    with {:ok, statement} <- Sqlite3.prepare(db, sql),
         :ok <- Sqlite3.bind(statement, params) do
      try do
        case Sqlite3.step(db, statement) do
          :done -> :ok
          {:row, _row} -> :ok
          {:error, reason} -> {:error, reason}
        end
      after
        _ = Sqlite3.release(db, statement)
      end
    end
  end

  defp query_all(db, sql, params \\ []) do
    with {:ok, statement} <- Sqlite3.prepare(db, sql),
         :ok <- Sqlite3.bind(statement, params) do
      try do
        collect_rows(db, statement, [])
      after
        _ = Sqlite3.release(db, statement)
      end
    else
      {:error, _reason} -> []
    end
  end

  defp collect_rows(db, statement, rows) do
    case Sqlite3.step(db, statement) do
      {:row, row} -> collect_rows(db, statement, [row | rows])
      :done -> Enum.reverse(rows)
      {:error, _reason} -> Enum.reverse(rows)
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(value), do: to_string(value)
end
