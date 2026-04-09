defmodule CollabExWeb.Plugs.ApiKeyAuthTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias CollabExWeb.Plugs.ApiKeyAuth

  setup do
    original = Application.get_env(:collabex_web, ApiKeyAuth)
    on_exit(fn -> Application.put_env(:collabex_web, ApiKeyAuth, original || []) end)
    :ok
  end

  test "allows request when no API keys configured (dev mode)" do
    Application.put_env(:collabex_web, ApiKeyAuth, api_keys: [])

    conn =
      conn(:get, "/api/rooms")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    refute conn.halted
  end

  test "rejects request with missing Authorization header" do
    Application.put_env(:collabex_web, ApiKeyAuth, api_keys: ["secret-key"])

    conn =
      conn(:get, "/api/rooms")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    assert conn.halted
    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "Missing API key"
  end

  test "rejects request with invalid API key" do
    Application.put_env(:collabex_web, ApiKeyAuth, api_keys: ["secret-key"])

    conn =
      conn(:get, "/api/rooms")
      |> put_req_header("authorization", "Bearer wrong-key")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    assert conn.halted
    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "Invalid API key"
  end

  test "allows request with valid API key" do
    Application.put_env(:collabex_web, ApiKeyAuth, api_keys: ["secret-key"])

    conn =
      conn(:get, "/api/rooms")
      |> put_req_header("authorization", "Bearer secret-key")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    refute conn.halted
  end

  test "accepts any of multiple configured keys" do
    Application.put_env(:collabex_web, ApiKeyAuth, api_keys: ["key-1", "key-2"])

    conn1 =
      conn(:get, "/api/rooms")
      |> put_req_header("authorization", "Bearer key-1")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    conn2 =
      conn(:get, "/api/rooms")
      |> put_req_header("authorization", "Bearer key-2")
      |> ApiKeyAuth.call(ApiKeyAuth.init([]))

    refute conn1.halted
    refute conn2.halted
  end
end
