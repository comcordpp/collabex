defmodule CollabEx.Document.Persistence do
  @moduledoc """
  Behaviour for document persistence adapters.

  Implement this behaviour to provide custom storage backends for room documents.
  Adapters must support both full state save/load and incremental update appending.
  """

  @doc "Load the compacted document state for a room."
  @callback load(room_id :: String.t()) :: {:ok, binary()} | {:error, :not_found | term()}

  @doc "Save the full compacted document state for a room."
  @callback save(room_id :: String.t(), state :: binary()) :: :ok | {:error, term()}

  @doc "Append an incremental update to the update log."
  @callback append_update(room_id :: String.t(), update :: binary()) :: :ok | {:error, term()}

  @doc "Compact pending updates into the base state. Returns the new base state."
  @callback compact(room_id :: String.t()) :: {:ok, binary()} | {:error, term()}

  @doc "Load all pending updates since last compaction."
  @callback load_updates(room_id :: String.t()) :: {:ok, [binary()]} | {:error, term()}

  @doc "Delete all stored state and updates for a room."
  @callback delete(room_id :: String.t()) :: :ok | {:error, term()}
end
