defmodule Jido.CampfireWeb.Presence do
  @moduledoc """
  Phoenix Presence tracker for the Campfire demo workspace.

  Campfire keeps Phoenix-specific realtime process tracking here, outside
  `jido_messaging`, so the messaging package stays transport agnostic.
  """

  use Phoenix.Presence,
    otp_app: :jido_campfire,
    pubsub_server: Jido.Campfire.PubSub
end
