defmodule CollabExWeb.RoomSocket do
  use Phoenix.Socket

  channel "room:*", CollabExWeb.RoomChannel

  @impl true
  def connect(params, socket, _connect_info) do
    client_id = Map.get(params, "client_id", generate_client_id())
    {:ok, assign(socket, :client_id, client_id)}
  end

  @impl true
  def id(socket), do: "client:#{socket.assigns.client_id}"

  defp generate_client_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
