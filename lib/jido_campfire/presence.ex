defmodule Jido.Campfire.Presence do
  @moduledoc """
  Campfire's Phoenix Presence adapter.

  `Jido.Messaging.Presence` owns the reusable session bookkeeping, Phoenix
  Presence calls, TTL pruning, and normalized participant signals. Campfire only
  configures the adapter.
  """

  alias Jido.Campfire.Seeds

  use Jido.Messaging.Presence,
    messaging: Jido.Campfire.Messaging,
    presence: Jido.CampfireWeb.Presence,
    topic: {__MODULE__, :presence_topic, []},
    source: "jido_campfire.presence",
    otp_app: :jido_campfire,
    signal_opts: [channel_type: :campfire, instance_id: "jido"],
    notify: {Jido.CampfireWeb.PresenceNotifier, :notify, []}

  def presence_topic do
    "campfire:presence:#{Seeds.workspace_id()}"
  end
end
