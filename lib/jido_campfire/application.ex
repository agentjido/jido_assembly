defmodule Jido.Campfire.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.CampfireWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jido_campfire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jido.Campfire.PubSub},
      Jido.Campfire.Messaging,
      Jido.Campfire.Chat.Seeds,
      # Start a worker by calling: Jido.Campfire.Worker.start_link(arg)
      # {Jido.Campfire.Worker, arg},
      # Start to serve requests, typically the last entry
      Jido.CampfireWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jido.Campfire.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Jido.CampfireWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
