defmodule Jido.Campfire.Messaging do
  @moduledoc """
  Campfire's local `jido_messaging` instance.

  The Hologram UI treats this module as the canonical room/message store. The
  developer demo uses a small SQLite-backed persistence adapter so rooms,
  participants, messages, reactions, and lightweight threads survive restarts.
  """

  use Jido.Messaging,
    persistence: Jido.Campfire.Persistence.SQLite,
    pubsub: Jido.Campfire.PubSub
end
