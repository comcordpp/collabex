defmodule CollabExWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", CollabExWeb do
    pipe_through :api

    get "/rooms", RoomController, :index
    get "/rooms/:room_id", RoomController, :show
    get "/rooms/:room_id/presence", RoomController, :presence
    delete "/rooms/:room_id", RoomController, :delete
  end

  scope "/metrics" do
    get "/", CollabExWeb.MetricsController, :index
  end
end
