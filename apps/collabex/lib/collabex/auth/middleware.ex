defmodule CollabEx.Auth.Middleware do
  @moduledoc """
  Behaviour for authentication middleware modules.

  Each middleware receives connection params, the current auth context,
  and its configuration options. It must return either:
  - `{:ok, updated_context}` to pass to the next middleware
  - `{:error, reason}` to reject the connection
  """

  @callback authenticate(
              params :: map(),
              context :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, atom() | String.t()}
end
