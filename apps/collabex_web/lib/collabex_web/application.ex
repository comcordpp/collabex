defmodule CollabExWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: CollabExWeb.PubSub},
      CollabExWeb.Presence,
      CollabExWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CollabExWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
