defmodule Jido.Campfire.Messaging do
  @moduledoc """
  Campfire's local `jido_messaging` instance.

  The spike keeps persistence in `Jido.Messaging.Persistence.ETS`, so app
  restarts reset the workspace. The Hologram UI treats this module as the
  canonical room/message store.
  """

  use Jido.Messaging,
    persistence: Jido.Messaging.Persistence.ETS,
    pubsub: Jido.Campfire.PubSub
end
