defmodule CollabExWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug CollabExWeb.Plugs.ApiKeyAuth
  end

  # Public read-only endpoints (room listing, info, presence)
  scope "/api", CollabExWeb do
    pipe_through :api

    get "/rooms", RoomController, :index
    get "/rooms/:room_id", RoomController, :show
    get "/rooms/:room_id/presence", RoomController, :presence
  end

  # Authenticated endpoints (document management, room mutations)
  scope "/api", CollabExWeb do
    pipe_through :api_auth

    get "/rooms/:room_id/document", RoomController, :export_document
    post "/rooms/:room_id/document", RoomController, :import_document
    delete "/rooms/:room_id", RoomController, :delete
  end

  scope "/metrics" do
    get "/", CollabExWeb.MetricsController, :index
  end
end
