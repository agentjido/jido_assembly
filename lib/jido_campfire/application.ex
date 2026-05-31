defmodule Jido.Campfire.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.CampfireWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jido_campfire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jido.Campfire.PubSub},
      Jido.CampfireWeb.Presence,
      {Jido.Campfire.Messaging,
       persistence_opts: [
         path: Application.get_env(:jido_campfire, :sqlite_path, "data/jido_campfire.sqlite3")
       ]},
      Jido.Campfire.Seeds,
      Jido.Campfire.Presence,
      Jido.CampfireWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Jido.Campfire.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Jido.CampfireWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
