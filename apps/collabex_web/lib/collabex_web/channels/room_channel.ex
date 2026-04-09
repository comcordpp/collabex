defmodule CollabExWeb.RoomChannel do
  @moduledoc """
  Phoenix Channel implementing the Yjs WebSocket sync protocol.

  Handles:
  - Yjs sync protocol v1 (sync step 1, sync step 2, update)
  - Yjs awareness protocol (cursor/selection sharing)
  - Phoenix Presence tracking with user metadata
  - Graceful reconnection with state resync

  ## Yjs Sync Protocol Message Types
  - `messageSync` (0): Sync protocol messages
    - syncStep1 (0): Client sends state vector, server responds with missing updates
    - syncStep2 (1): Server sends state vector response
    - update (2): Incremental document update
  - `messageAwareness` (1): Awareness state updates (cursors, selections)

  Clients send binary frames; this channel handles them via the `"yjs"` event
  with base64-encoded data for Phoenix Channel JSON transport.
  """

  use Phoenix.Channel

  alias CollabEx.Room.{Manager, Server}
  alias CollabExWeb.Presence

  require Logger

  # Yjs protocol message types
  @message_sync 0
  @message_awareness 1

  # Yjs sync sub-message types
  @sync_step1 0
  @sync_step2 1
  @sync_update 2

  @impl true
  def join("room:" <> room_id, _params, socket) do
    client_id = socket.assigns.client_id
    auth_context = socket.assigns[:auth_context] || %{}

    # Ensure room process exists
    case Manager.get_or_create_room(room_id) do
      {:ok, _pid} ->
        # Register this channel process as a client with auth context
        {:ok, doc_state} = Server.join(room_id, client_id, self(), auth_context)

        socket =
          socket
          |> assign(:room_id, room_id)
          |> assign(:awareness_states, %{})

        # Track presence after join
        send(self(), :after_join)

        # Send initial document state to the joining client
        if doc_state do
          send(self(), {:send_sync_step1, doc_state})
        end

        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("yjs", %{"data" => encoded_data}, socket) do
    case Base.decode64(encoded_data) do
      {:ok, binary_data} ->
        handle_yjs_message(binary_data, socket)

      :error ->
        {:reply, {:error, %{reason: "invalid base64 encoding"}}, socket}
    end
  end

  @impl true
  def handle_in("awareness", %{"data" => encoded_data} = payload, socket) do
    case Base.decode64(encoded_data) do
      {:ok, _binary_data} ->
        client_id = socket.assigns.client_id

        # Extract awareness metadata if provided alongside the binary data
        cursor = Map.get(payload, "cursor")
        name = Map.get(payload, "name")
        color = Map.get(payload, "color")

        # Update server-side awareness state
        awareness_update = %{}
        awareness_update = if cursor, do: Map.put(awareness_update, :cursor, cursor), else: awareness_update
        awareness_update = if name, do: Map.put(awareness_update, :name, name), else: awareness_update
        awareness_update = if color, do: Map.put(awareness_update, :color, color), else: awareness_update

        socket =
          if map_size(awareness_update) > 0 do
            new_states = Map.merge(
              Map.get(socket.assigns.awareness_states, client_id, %{}),
              awareness_update
            )

            new_awareness = Map.put(socket.assigns.awareness_states, client_id, new_states)

            # Update presence metadata with awareness info
            Presence.update(socket, presence_key(socket), fn meta ->
              Map.merge(meta, awareness_update)
            end)

            assign(socket, :awareness_states, new_awareness)
          else
            socket
          end

        # Broadcast awareness binary to other clients in the room
        broadcast_from!(socket, "awareness", %{
          data: encoded_data,
          client_id: client_id
        })

        {:noreply, socket}

      :error ->
        {:reply, {:error, %{reason: "invalid base64 encoding"}}, socket}
    end
  end

  @impl true
  def handle_in("presence_state", _payload, socket) do
    # Client requests current presence state
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track this user in Phoenix Presence
    {:ok, _ref} =
      Presence.track(socket, presence_key(socket), %{
        client_id: socket.assigns.client_id,
        user_id: socket.assigns[:user_id],
        name: get_in(socket.assigns, [:auth_context, :name]),
        color: generate_user_color(socket.assigns.client_id),
        cursor: nil,
        online_at: System.system_time(:second)
      })

    # Push current presence state to the newly joined client
    push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:send_sync_step1, doc_state}, socket) do
    # Send the full document state to the newly connected client
    encoded = Base.encode64(doc_state)

    push(socket, "yjs", %{
      type: "sync",
      step: "full_state",
      data: encoded
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:yjs_update, _room_id, update}, socket) do
    # Forward Yjs update from room server to this client
    push(socket, "yjs", %{
      type: "update",
      data: Base.encode64(update)
    })

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if room_id = socket.assigns[:room_id] do
      Server.leave(room_id, socket.assigns.client_id)
    end

    # Presence is automatically cleaned up when the channel process exits
    :ok
  end

  # --- Private: Yjs message handling ---

  defp handle_yjs_message(<<@message_sync, @sync_step1, _rest::binary>>, socket) do
    # Client sends state vector -> we need to respond with missing updates
    room_id = socket.assigns.room_id

    case Server.get_state(room_id) do
      {:ok, doc_state} when not is_nil(doc_state) ->
        # Send full state as sync step 2 response
        push(socket, "yjs", %{
          type: "sync",
          step: "step2",
          data: Base.encode64(doc_state)
        })

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  defp handle_yjs_message(<<@message_sync, @sync_step2, rest::binary>>, socket) do
    # Server-side sync step 2 — apply the state from client
    room_id = socket.assigns.room_id
    client_id = socket.assigns.client_id
    Server.apply_update(room_id, rest, client_id)
    {:noreply, socket}
  end

  defp handle_yjs_message(<<@message_sync, @sync_update, rest::binary>>, socket) do
    # Incremental update from client
    room_id = socket.assigns.room_id
    client_id = socket.assigns.client_id
    Server.apply_update(room_id, rest, client_id)
    {:noreply, socket}
  end

  defp handle_yjs_message(<<@message_awareness, rest::binary>>, socket) do
    # Awareness update — broadcast to other clients
    broadcast_from!(socket, "awareness", %{
      data: Base.encode64(rest),
      client_id: socket.assigns.client_id
    })

    {:noreply, socket}
  end

  defp handle_yjs_message(_unknown, socket) do
    Logger.debug("Unknown Yjs message in room #{socket.assigns.room_id}")
    {:noreply, socket}
  end

  # --- Private: Presence helpers ---

  defp presence_key(socket) do
    socket.assigns[:user_id] || socket.assigns.client_id
  end

  defp generate_user_color(client_id) do
    # Deterministic color from client_id for consistent user identification
    colors = [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7",
      "#DDA0DD", "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E9",
      "#F8C471", "#82E0AA", "#F1948A", "#AED6F1", "#D7BDE2"
    ]

    index = :erlang.phash2(client_id, length(colors))
    Enum.at(colors, index)
  end
end
