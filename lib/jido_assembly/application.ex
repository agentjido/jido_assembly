defmodule Jido.Assembly.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.AssemblyWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jido_assembly, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jido.Assembly.PubSub},
      Jido.Assembly.Jido,
      Jido.AssemblyWeb.Presence,
      {Jido.Assembly.Messaging,
       persistence_opts: [
         path: Application.get_env(:jido_assembly, :sqlite_path, "data/jido_assembly.sqlite3")
       ]},
      Jido.Assembly.Seeds,
      Jido.Assembly.Presence,
      Jido.AssemblyWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Jido.Assembly.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Jido.AssemblyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
