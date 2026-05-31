defmodule Jido.Campfire.Chat.Seeds do
  @moduledoc false

  use GenServer

  alias Jido.Campfire.Chat

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Chat.ensure_seeded!()
    {:ok, %{}}
  end
end
