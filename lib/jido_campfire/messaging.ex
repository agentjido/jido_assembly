defmodule Jido.Campfire.Messaging do
  @moduledoc """
  Campfire's local `jido_messaging` instance.

  The Hologram UI treats this module as the canonical room/message store. The
  developer demo uses a small SQLite-backed persistence adapter so rooms,
  participants, messages, reactions, and lightweight threads survive restarts.
  """

  use Jido.Messaging,
    persistence: Jido.Messaging.Persistence.SQLite,
    persistence_opts: [path: "data/jido_campfire.sqlite3"],
    pubsub: Jido.Campfire.PubSub
end
