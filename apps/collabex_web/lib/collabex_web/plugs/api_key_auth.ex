defmodule CollabExWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Plug for API key authentication on server-to-server REST endpoints.

  Validates the `Authorization: Bearer <api_key>` header against configured
  API keys.

  ## Configuration

      config :collabex_web, CollabExWeb.Plugs.ApiKeyAuth,
        api_keys: ["key1", "key2"]

  If no API keys are configured, all requests are allowed (development mode).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case configured_keys() do
      [] ->
        # No keys configured — allow all (development mode)
        conn

      keys ->
        case get_bearer_token(conn) do
          nil ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{error: "Missing API key"}))
            |> halt()

          token ->
            if Enum.any?(keys, &Plug.Crypto.secure_compare(&1, token)) do
              conn
            else
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(401, Jason.encode!(%{error: "Invalid API key"}))
              |> halt()
            end
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp configured_keys do
    Application.get_env(:collabex_web, __MODULE__, [])
    |> Keyword.get(:api_keys, [])
  end
end
