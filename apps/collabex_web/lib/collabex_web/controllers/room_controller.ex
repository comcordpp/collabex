defmodule CollabExWeb.RoomController do
  use Phoenix.Controller, formats: [:json]

  alias CollabEx.Room.{Manager, Server}
  alias CollabExWeb.Presence

  def index(conn, _params) do
    rooms = Manager.list_rooms_info()
    json(conn, %{data: rooms})
  end

  def show(conn, %{"room_id" => room_id}) do
    case Manager.lookup(room_id) do
      {:ok, _pid} ->
        info = Server.info(room_id)
        presence = Presence.list_for_room(room_id)
        json(conn, %{data: Map.put(info, :presence, presence)})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end

  def presence(conn, %{"room_id" => room_id}) do
    case Manager.lookup(room_id) do
      {:ok, _pid} ->
        users = Presence.list_for_room(room_id)
        json(conn, %{data: users})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end

  def export_document(conn, %{"room_id" => room_id} = params) do
    case Manager.lookup(room_id) do
      {:ok, _pid} ->
        case Server.get_state(room_id) do
          {:ok, nil} ->
            conn |> put_status(:not_found) |> json(%{error: "Document has no state"})

          {:ok, doc_state} ->
            format = Map.get(params, "format", "base64")
            export_in_format(conn, room_id, doc_state, format)
        end

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end

  def import_document(conn, %{"room_id" => room_id} = params) do
    # Ensure the room exists (create if needed)
    case Manager.get_or_create_room(room_id) do
      {:ok, _pid} ->
        case decode_document_payload(params) do
          {:ok, binary_state} ->
            :ok = Server.set_state(room_id, binary_state)

            json(conn, %{
              data: %{
                room_id: room_id,
                document_size: byte_size(binary_state),
                message: "Document imported successfully"
              }
            })

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: reason})
        end

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create room: #{inspect(reason)}"})
    end
  end

  def delete(conn, %{"room_id" => room_id}) do
    case Manager.stop_room(room_id) do
      :ok -> conn |> put_status(:no_content) |> send_resp(204, "")
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Room not found"})
    end
  end

  # --- Private ---

  defp export_in_format(conn, room_id, doc_state, "base64") do
    json(conn, %{
      data: %{
        room_id: room_id,
        format: "base64",
        document: Base.encode64(doc_state),
        document_size: byte_size(doc_state)
      }
    })
  end

  defp export_in_format(conn, room_id, doc_state, "binary") do
    conn
    |> put_resp_content_type("application/octet-stream")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{room_id}.yjs\"")
    |> send_resp(200, doc_state)
  end

  defp export_in_format(conn, _room_id, _doc_state, format) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Unsupported format: #{format}. Use 'base64' or 'binary'."})
  end

  defp decode_document_payload(%{"document" => encoded}) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, "Invalid base64 in 'document' field"}
    end
  end

  defp decode_document_payload(_) do
    {:error, "Missing 'document' field with base64-encoded Yjs state"}
  end
end
