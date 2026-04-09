defmodule CollabExWeb.RoomChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias CollabExWeb.{Presence, RoomSocket}

  @endpoint CollabExWeb.Endpoint

  setup do
    # Ensure open auth pipeline
    original_auth = Application.get_env(:collabex, CollabEx.Auth)
    Application.put_env(:collabex, CollabEx.Auth, pipeline: [])
    on_exit(fn -> Application.put_env(:collabex, CollabEx.Auth, original_auth || []) end)

    room_id = "test-room-#{System.unique_integer([:positive])}"

    {:ok, socket} =
      connect(RoomSocket, %{"client_id" => "client-1"})

    {:ok, socket: socket, room_id: room_id}
  end

  describe "join/3" do
    test "successfully joins a room and receives presence_state", %{socket: socket, room_id: room_id} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "room:#{room_id}", %{})

      # After join, we should receive a presence_state push
      assert_push "presence_state", %{}
    end

    test "tracks user in presence on join", %{socket: socket, room_id: room_id} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "room:#{room_id}", %{})

      # Allow presence tracking to complete
      assert_push "presence_state", presence

      # The joining user should appear in presence
      assert map_size(presence) >= 1
    end

    test "presence includes metadata with client_id, color, and online_at", %{socket: socket, room_id: room_id} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, "room:#{room_id}", %{})

      assert_push "presence_state", presence

      # Find our user's presence entry
      {_key, %{metas: [meta | _]}} =
        Enum.find(presence, fn {_key, _val} -> true end)

      assert meta.client_id == "client-1"
      assert is_binary(meta.color)
      assert is_integer(meta.online_at)
    end
  end

  describe "presence tracking with multiple users" do
    test "second user sees first user in presence_state", %{room_id: room_id} do
      # First user joins
      {:ok, socket1} = connect(RoomSocket, %{"client_id" => "client-1"})
      {:ok, _reply, _socket1} = subscribe_and_join(socket1, "room:#{room_id}", %{})
      assert_push "presence_state", _

      # Second user joins
      {:ok, socket2} = connect(RoomSocket, %{"client_id" => "client-2"})
      {:ok, _reply, _socket2} = subscribe_and_join(socket2, "room:#{room_id}", %{})

      # The second user should see presence including the first user
      assert_push "presence_state", presence
      assert map_size(presence) >= 1
    end

    test "presence_diff broadcast on join", %{room_id: room_id} do
      # First user joins
      {:ok, socket1} = connect(RoomSocket, %{"client_id" => "client-1"})
      {:ok, _reply, _socket1} = subscribe_and_join(socket1, "room:#{room_id}", %{})
      assert_push "presence_state", _

      # Second user joins — first user should receive a presence_diff
      {:ok, socket2} = connect(RoomSocket, %{"client_id" => "client-2"})
      {:ok, _reply, _socket2} = subscribe_and_join(socket2, "room:#{room_id}", %{})

      assert_broadcast "presence_diff", %{joins: joins, leaves: _leaves}
      assert map_size(joins) >= 1
    end
  end

  describe "awareness" do
    test "awareness messages are broadcast to other clients", %{room_id: room_id} do
      {:ok, socket1} = connect(RoomSocket, %{"client_id" => "client-1"})
      {:ok, _reply, socket1} = subscribe_and_join(socket1, "room:#{room_id}", %{})
      assert_push "presence_state", _

      {:ok, socket2} = connect(RoomSocket, %{"client_id" => "client-2"})
      {:ok, _reply, _socket2} = subscribe_and_join(socket2, "room:#{room_id}", %{})
      assert_push "presence_state", _

      # Client 1 sends awareness update
      awareness_data = Base.encode64("awareness-binary-data")

      push(socket1, "awareness", %{
        "data" => awareness_data,
        "cursor" => %{"x" => 10, "y" => 20},
        "name" => "Alice",
        "color" => "#FF0000"
      })

      # Client 2 should receive the awareness broadcast
      assert_broadcast "awareness", %{data: ^awareness_data, client_id: "client-1"}
    end

    test "awareness updates presence metadata", %{socket: socket, room_id: room_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, "room:#{room_id}", %{})
      assert_push "presence_state", _

      awareness_data = Base.encode64("test")

      push(socket, "awareness", %{
        "data" => awareness_data,
        "cursor" => %{"line" => 5, "ch" => 10},
        "name" => "TestUser"
      })

      # Give a moment for the presence update to propagate
      Process.sleep(50)

      # Check presence was updated with awareness info
      presence_list = Presence.list_for_room(room_id)
      user = Enum.find(presence_list, &(&1.client_id == "client-1"))
      assert user.name == "TestUser"
      assert user.cursor == %{"line" => 5, "ch" => 10}
    end
  end

  describe "presence_state request" do
    test "client can request current presence state", %{socket: socket, room_id: room_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, "room:#{room_id}", %{})
      assert_push "presence_state", _

      # Request presence state explicitly
      push(socket, "presence_state", %{})
      assert_push "presence_state", presence
      assert map_size(presence) >= 1
    end
  end

  describe "Presence.list_for_room/1" do
    test "returns formatted user list for a room", %{room_id: room_id} do
      {:ok, socket1} = connect(RoomSocket, %{"client_id" => "client-1"})
      {:ok, _reply, _socket1} = subscribe_and_join(socket1, "room:#{room_id}", %{})
      assert_push "presence_state", _

      users = Presence.list_for_room(room_id)
      assert length(users) == 1

      [user] = users
      assert user.client_id == "client-1"
      assert is_binary(user.color)
      assert is_integer(user.online_at)
      assert is_nil(user.cursor)
    end

    test "returns empty list for room with no users" do
      assert [] == Presence.list_for_room("nonexistent-room")
    end
  end

  describe "disconnect cleanup" do
    test "presence is removed when channel process exits", %{room_id: room_id} do
      {:ok, socket1} = connect(RoomSocket, %{"client_id" => "client-1"})
      {:ok, _reply, socket1} = subscribe_and_join(socket1, "room:#{room_id}", %{})
      assert_push "presence_state", _

      # Verify user is present
      assert length(Presence.list_for_room(room_id)) == 1

      # Leave the channel
      Process.unlink(socket1.channel_pid)
      close(socket1)

      # Allow presence cleanup
      Process.sleep(100)

      assert length(Presence.list_for_room(room_id)) == 0
    end
  end
end
