defmodule CollabEx.Auth.Middleware.JWTTest do
  use ExUnit.Case, async: true

  alias CollabEx.Auth.Middleware.JWT

  @secret "test-secret-key"
  @issuer "test-app"

  defp make_jwt(claims, secret \\ @secret) do
    header = Base.url_encode64(Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)
    signature = :crypto.mac(:hmac, :sha256, secret, "#{header}.#{payload}")
    |> Base.url_encode64(padding: false)
    "#{header}.#{payload}.#{signature}"
  end

  defp opts(extra \\ []) do
    Keyword.merge([secret: @secret, issuer: @issuer], extra)
  end

  test "valid JWT extracts user_id and permissions" do
    token = make_jwt(%{"sub" => "user-123", "permissions" => ["read", "write"], "iss" => @issuer})
    params = %{"token" => token}

    assert {:ok, context} = JWT.authenticate(params, %{}, opts())
    assert context.user_id == "user-123"
    assert context.permissions == ["read", "write"]
    assert context.claims["sub"] == "user-123"
  end

  test "missing token returns error" do
    assert {:error, :missing_token} = JWT.authenticate(%{}, %{}, opts())
  end

  test "malformed token returns error" do
    assert {:error, :malformed_token} = JWT.authenticate(%{"token" => "not-a-jwt"}, %{}, opts())
  end

  test "invalid signature returns error" do
    token = make_jwt(%{"sub" => "user-123", "iss" => @issuer}, "wrong-secret")
    assert {:error, :invalid_signature} = JWT.authenticate(%{"token" => token}, %{}, opts())
  end

  test "expired token returns error" do
    expired_at = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.-(3600)
    token = make_jwt(%{"sub" => "user-123", "iss" => @issuer, "exp" => expired_at})
    assert {:error, :token_expired} = JWT.authenticate(%{"token" => token}, %{}, opts())
  end

  test "wrong issuer returns error" do
    token = make_jwt(%{"sub" => "user-123", "iss" => "wrong-issuer"})
    assert {:error, :invalid_issuer} = JWT.authenticate(%{"token" => token}, %{}, opts())
  end

  test "custom param_key" do
    token = make_jwt(%{"sub" => "user-123", "iss" => @issuer})
    params = %{"auth" => token}
    assert {:ok, _} = JWT.authenticate(params, %{}, opts(param_key: "auth"))
    assert {:error, :missing_token} = JWT.authenticate(params, %{}, opts(param_key: "token"))
  end

  test "no issuer validation when issuer not configured" do
    token = make_jwt(%{"sub" => "user-123", "iss" => "any-issuer"})
    assert {:ok, _} = JWT.authenticate(%{"token" => token}, %{}, [secret: @secret])
  end

  test "merges into existing context" do
    token = make_jwt(%{"sub" => "user-123", "iss" => @issuer})
    existing = %{org_id: "org-456"}
    assert {:ok, context} = JWT.authenticate(%{"token" => token}, existing, opts())
    assert context.org_id == "org-456"
    assert context.user_id == "user-123"
  end
end
