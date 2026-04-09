defmodule CollabExWeb.PresenceTest do
  use ExUnit.Case, async: true

  alias CollabExWeb.Presence

  describe "disconnect_timeout/0" do
    test "returns default of 30_000 when not configured" do
      original = Application.get_env(:collabex_web, Presence)
      Application.delete_env(:collabex_web, Presence)
      on_exit(fn -> if original, do: Application.put_env(:collabex_web, Presence, original) end)

      assert Presence.disconnect_timeout() == 30_000
    end

    test "returns configured value" do
      original = Application.get_env(:collabex_web, Presence)
      Application.put_env(:collabex_web, Presence, disconnect_timeout: 60_000)
      on_exit(fn -> Application.put_env(:collabex_web, Presence, original || []) end)

      assert Presence.disconnect_timeout() == 60_000
    end
  end

  describe "list_for_room/1" do
    test "returns empty list for nonexistent room" do
      assert Presence.list_for_room("does-not-exist-#{System.unique_integer()}") == []
    end
  end
end
