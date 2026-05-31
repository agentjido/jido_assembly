defmodule Jido.CampfireWeb.PageController do
  use Jido.CampfireWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
