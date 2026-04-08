defmodule CollabExWeb.RoomSocket do
  use Phoenix.Socket

  require Logger

  channel "room:*", CollabExWeb.RoomChannel

  @impl true
  def connect(params, socket, _connect_info) do
    client_id = Map.get(params, "client_id", generate_client_id())

    # Run auth pipeline
    case CollabEx.Auth.authenticate(params) do
      {:ok, auth_context} ->
        socket =
          socket
          |> assign(:client_id, client_id)
          |> assign(:auth_context, auth_context)
          |> assign(:user_id, Map.get(auth_context, :user_id))
          |> assign(:permissions, Map.get(auth_context, :permissions, []))

        {:ok, socket}

      {:error, reason} ->
        Logger.info("WebSocket auth rejected: #{inspect(reason)}")
        :error
    end
  end

  @impl true
  def id(socket) do
    case socket.assigns[:user_id] do
      nil -> "client:#{socket.assigns.client_id}"
      user_id -> "user:#{user_id}"
    end
  end

  defp generate_client_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
