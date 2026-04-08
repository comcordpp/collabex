defmodule CollabExWeb.RoomController do
  use Phoenix.Controller, formats: [:json]

  alias CollabEx.Room.{Manager, Server}

  def index(conn, _params) do
    rooms = Manager.list_rooms_info()
    json(conn, %{data: rooms})
  end

  def show(conn, %{"room_id" => room_id}) do
    case Manager.lookup(room_id) do
      {:ok, _pid} ->
        info = Server.info(room_id)
        json(conn, %{data: info})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end

  def delete(conn, %{"room_id" => room_id}) do
    case Manager.stop_room(room_id) do
      :ok -> conn |> put_status(:no_content) |> send_resp(204, "")
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end
end
