defmodule CollabEx.Auth.Middleware.CustomTest do
  use ExUnit.Case, async: true

  alias CollabEx.Auth.Middleware.Custom

  test "delegates to provided auth function" do
    auth_fn = fn _params, context ->
      {:ok, Map.put(context, :custom_user, "alice")}
    end

    assert {:ok, %{custom_user: "alice"}} = Custom.authenticate(%{}, %{}, auth_fn: auth_fn)
  end

  test "passes params and context to auth function" do
    auth_fn = fn params, context ->
      {:ok, Map.merge(context, %{token: params["token"], seen: true})}
    end

    params = %{"token" => "abc"}
    assert {:ok, ctx} = Custom.authenticate(params, %{base: true}, auth_fn: auth_fn)
    assert ctx.token == "abc"
    assert ctx.base == true
    assert ctx.seen == true
  end

  test "error from auth function propagates" do
    auth_fn = fn _params, _context -> {:error, :custom_denied} end
    assert {:error, :custom_denied} = Custom.authenticate(%{}, %{}, auth_fn: auth_fn)
  end

  test "unexpected return from auth function returns authentication_failed" do
    auth_fn = fn _params, _context -> :something_weird end
    assert {:error, :authentication_failed} = Custom.authenticate(%{}, %{}, auth_fn: auth_fn)
  end
end
