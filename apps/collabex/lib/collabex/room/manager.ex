defmodule CollabEx.Room.Manager do
  @moduledoc """
  Manages room process lifecycle — creates rooms on demand and provides lookup.
  """

  alias CollabEx.Room.Server

  @doc """
  Get or create a room process for the given room_id.
  Returns `{:ok, pid}` on success.
  """
  def get_or_create_room(room_id, opts \\ []) do
    case lookup(room_id) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        start_room(room_id, opts)
    end
  end

  @doc "Look up an existing room by ID."
  def lookup(room_id) do
    case Registry.lookup(CollabEx.RoomRegistry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc "Check if a room exists."
  def room_exists?(room_id) do
    match?({:ok, _}, lookup(room_id))
  end

  @doc "List all active room IDs."
  def list_rooms do
    CollabEx.RoomRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc "Get info for all active rooms."
  def list_rooms_info do
    list_rooms()
    |> Enum.map(fn room_id ->
      try do
        Server.info(room_id)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Forcefully stop a room."
  def stop_room(room_id) do
    case lookup(room_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(CollabEx.RoomSupervisor, pid)
      :error -> {:error, :not_found}
    end
  end

  # --- Private ---

  defp start_room(room_id, opts) do
    child_spec = {Server, Keyword.put(opts, :room_id, room_id)}

    case DynamicSupervisor.start_child(CollabEx.RoomSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end
end
