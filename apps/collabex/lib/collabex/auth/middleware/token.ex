defmodule CollabEx.Auth.Middleware.Token do
  @moduledoc """
  Simple token-based authentication middleware.

  Validates a bearer token against a lookup function.

  ## Configuration

      {CollabEx.Auth.Middleware.Token,
        lookup: &MyApp.Tokens.validate/1,
        param_key: "token"  # default: "token"
      }
  """

  @behaviour CollabEx.Auth.Middleware

  @impl true
  def authenticate(params, context, opts) do
    param_key = Keyword.get(opts, :param_key, "token")
    lookup_fn = Keyword.fetch!(opts, :lookup)

    case Map.get(params, param_key) do
      nil ->
        {:error, :missing_token}

      token ->
        case lookup_fn.(token) do
          {:ok, user_info} when is_map(user_info) ->
            {:ok, Map.merge(context, user_info)}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :invalid_token}
        end
    end
  end
end
