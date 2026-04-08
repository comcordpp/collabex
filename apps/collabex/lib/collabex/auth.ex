defmodule CollabEx.Auth do
  @moduledoc """
  Authentication pipeline for CollabEx WebSocket connections.

  Runs an ordered list of middleware modules on connect. Each middleware
  can either pass (returning enriched context) or reject the connection.

  ## Configuration

      config :collabex, CollabEx.Auth,
        pipeline: [
          {CollabEx.Auth.Middleware.JWT, issuer: "my-app", secret: "..."},
          {CollabEx.Auth.Middleware.RoomAccess, []}
        ]

  ## Custom Middleware

  Implement the `CollabEx.Auth.Middleware` behaviour:

      defmodule MyApp.Auth.Custom do
        @behaviour CollabEx.Auth.Middleware

        @impl true
        def authenticate(params, context, _opts) do
          case validate(params) do
            {:ok, user} -> {:ok, Map.put(context, :user, user)}
            :error -> {:error, :unauthorized}
          end
        end
      end
  """

  @doc """
  Run the authentication pipeline against connection params.
  Returns `{:ok, context}` or `{:error, reason}`.
  """
  def authenticate(params, initial_context \\ %{}) do
    pipeline = Application.get_env(:collabex, __MODULE__, []) |> Keyword.get(:pipeline, [])
    run_pipeline(pipeline, params, initial_context)
  end

  defp run_pipeline([], _params, context), do: {:ok, context}

  defp run_pipeline([{module, opts} | rest], params, context) do
    case module.authenticate(params, context, opts) do
      {:ok, new_context} -> run_pipeline(rest, params, new_context)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_pipeline([module | rest], params, context) when is_atom(module) do
    run_pipeline([{module, []} | rest], params, context)
  end
end
