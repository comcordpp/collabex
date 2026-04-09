defmodule CollabEx.Auth.Middleware.TokenTest do
  use ExUnit.Case, async: true

  alias CollabEx.Auth.Middleware.Token

  @valid_token "valid-token-abc"

  defp lookup(token) do
    if token == @valid_token do
      {:ok, %{user_id: "user-from-token", role: "editor"}}
    else
      {:error, :invalid_token}
    end
  end

  defp opts(extra \\ []) do
    Keyword.merge([lookup: &lookup/1], extra)
  end

  test "valid token returns user info merged into context" do
    params = %{"token" => @valid_token}
    assert {:ok, context} = Token.authenticate(params, %{}, opts())
    assert context.user_id == "user-from-token"
    assert context.role == "editor"
  end

  test "missing token returns error" do
    assert {:error, :missing_token} = Token.authenticate(%{}, %{}, opts())
  end

  test "invalid token returns lookup error" do
    assert {:error, :invalid_token} = Token.authenticate(%{"token" => "bad"}, %{}, opts())
  end

  test "custom param_key" do
    params = %{"api_key" => @valid_token}
    assert {:ok, _} = Token.authenticate(params, %{}, opts(param_key: "api_key"))
  end

  test "merges into existing context" do
    params = %{"token" => @valid_token}
    assert {:ok, context} = Token.authenticate(params, %{org: "acme"}, opts())
    assert context.org == "acme"
    assert context.user_id == "user-from-token"
  end
end
