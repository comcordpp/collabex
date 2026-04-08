defmodule CollabEx.Auth.Middleware.Custom do
  @moduledoc """
  Custom function authentication middleware.

  Delegates authentication to a user-provided function.

  ## Configuration

      {CollabEx.Auth.Middleware.Custom,
        auth_fn: fn params, context ->
          case MyApp.Auth.verify(params["token"]) do
            {:ok, user} -> {:ok, Map.put(context, :user, user)}
            :error -> {:error, :unauthorized}
          end
        end
      }
  """

  @behaviour CollabEx.Auth.Middleware

  @impl true
  def authenticate(params, context, opts) do
    auth_fn = Keyword.fetch!(opts, :auth_fn)

    case auth_fn.(params, context) do
      {:ok, new_context} when is_map(new_context) -> {:ok, new_context}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_failed}
    end
  end
end
