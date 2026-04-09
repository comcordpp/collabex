defmodule CollabExWeb.RoomControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias CollabExWeb.{Endpoint, Router}

  @opts Router.init([])

  setup do
    # Ensure open auth pipeline and no API key requirement
    original_auth = Application.get_env(:collabex, CollabEx.Auth)
    original_api_keys = Application.get_env(:collabex_web, CollabExWeb.Plugs.ApiKeyAuth)

    Application.put_env(:collabex, CollabEx.Auth, pipeline: [])
    Application.put_env(:collabex_web, CollabExWeb.Plugs.ApiKeyAuth, api_keys: [])

    on_exit(fn ->
      Application.put_env(:collabex, CollabEx.Auth, original_auth || [])
      Application.put_env(:collabex_web, CollabExWeb.Plugs.ApiKeyAuth, original_api_keys || [])
    end)

    room_id = "test-room-#{System.unique_integer([:positive])}"

    {:ok, room_id: room_id}
  end

  describe "GET /api/rooms" do
    test "returns empty list when no rooms" do
      conn =
        conn(:get, "/api/rooms")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_list(body["data"])
    end
  end

  describe "GET /api/rooms/:room_id" do
    test "returns 404 for nonexistent room" do
      conn =
        conn(:get, "/api/rooms/nonexistent-#{System.unique_integer([:positive])}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "GET /api/rooms/:room_id/document" do
    test "returns 404 for nonexistent room", %{room_id: room_id} do
      conn =
        conn(:get, "/api/rooms/nonexistent-#{room_id}/document")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "POST /api/rooms/:room_id/document" do
    test "imports a document into a new room", %{room_id: room_id} do
      doc_content = Base.encode64("hello-yjs-state")

      conn =
        conn(:post, "/api/rooms/#{room_id}/document", Jason.encode!(%{document: doc_content}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["room_id"] == room_id
      assert body["data"]["document_size"] > 0

      # Verify the state was actually set
      {:ok, state} = CollabEx.Room.Server.get_state(room_id)
      assert state == "hello-yjs-state"
    end

    test "rejects invalid base64", %{room_id: room_id} do
      conn =
        conn(:post, "/api/rooms/#{room_id}/document", Jason.encode!(%{document: "not-valid-base64!!!"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
    end

    test "rejects missing document field", %{room_id: room_id} do
      conn =
        conn(:post, "/api/rooms/#{room_id}/document", Jason.encode!(%{foo: "bar"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
    end
  end

  describe "DELETE /api/rooms/:room_id" do
    test "returns 404 for nonexistent room" do
      conn =
        conn(:delete, "/api/rooms/nonexistent-#{System.unique_integer([:positive])}")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "API key auth on protected endpoints" do
    test "rejects unauthenticated delete when keys configured" do
      Application.put_env(:collabex_web, CollabExWeb.Plugs.ApiKeyAuth, api_keys: ["test-key"])

      conn =
        conn(:delete, "/api/rooms/some-room")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 401
    end

    test "allows authenticated delete when keys configured" do
      Application.put_env(:collabex_web, CollabExWeb.Plugs.ApiKeyAuth, api_keys: ["test-key"])

      conn =
        conn(:delete, "/api/rooms/some-room")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-key")
        |> Router.call(@opts)

      # 404 because room doesn't exist, but auth passed
      assert conn.status == 404
    end
  end
end
