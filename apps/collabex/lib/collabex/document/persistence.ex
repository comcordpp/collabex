defmodule CollabEx.Document.Persistence do
  @moduledoc """
  Behaviour for document persistence adapters.

  Implement this behaviour to provide custom storage backends for room documents.
  """

  @doc "Load document state for a room."
  @callback load(room_id :: String.t()) :: {:ok, binary()} | {:error, :not_found | term()}

  @doc "Save document state for a room."
  @callback save(room_id :: String.t(), state :: binary()) :: :ok | {:error, term()}

  @doc "Delete document state for a room."
  @callback delete(room_id :: String.t()) :: :ok | {:error, term()}
end
