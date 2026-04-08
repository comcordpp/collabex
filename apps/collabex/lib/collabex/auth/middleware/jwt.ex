defmodule CollabEx.Auth.Middleware.JWT do
  @moduledoc """
  JWT authentication middleware.

  Validates a JWT token from the connection params and extracts user identity.

  ## Configuration

      {CollabEx.Auth.Middleware.JWT,
        secret: "your-secret-key",
        issuer: "your-app",
        param_key: "token"  # default: "token"
      }
  """

  @behaviour CollabEx.Auth.Middleware

  @impl true
  def authenticate(params, context, opts) do
    param_key = Keyword.get(opts, :param_key, "token")
    secret = Keyword.fetch!(opts, :secret)

    case Map.get(params, param_key) do
      nil ->
        {:error, :missing_token}

      token ->
        case verify_jwt(token, secret, opts) do
          {:ok, claims} ->
            auth_context = %{
              user_id: Map.get(claims, "sub"),
              permissions: Map.get(claims, "permissions", []),
              claims: claims
            }

            {:ok, Map.merge(context, auth_context)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp verify_jwt(token, secret, opts) do
    # Simple HMAC-SHA256 JWT verification
    # In production, use a proper JWT library (joken, guardian)
    case String.split(token, ".") do
      [header_b64, payload_b64, signature_b64] ->
        expected_sig = :crypto.mac(:hmac, :sha256, secret, "#{header_b64}.#{payload_b64}")
        |> Base.url_encode64(padding: false)

        if secure_compare(signature_b64, expected_sig) do
          case Base.url_decode64(payload_b64, padding: false) do
            {:ok, payload_json} ->
              case Jason.decode(payload_json) do
                {:ok, claims} -> validate_claims(claims, opts)
                _ -> {:error, :invalid_token}
              end

            _ ->
              {:error, :invalid_token}
          end
        else
          {:error, :invalid_signature}
        end

      _ ->
        {:error, :malformed_token}
    end
  end

  defp validate_claims(claims, opts) do
    issuer = Keyword.get(opts, :issuer)

    cond do
      issuer && Map.get(claims, "iss") != issuer ->
        {:error, :invalid_issuer}

      Map.has_key?(claims, "exp") && expired?(claims["exp"]) ->
        {:error, :token_expired}

      true ->
        {:ok, claims}
    end
  end

  defp expired?(exp) when is_integer(exp) do
    DateTime.utc_now() |> DateTime.to_unix() > exp
  end

  defp expired?(_), do: false

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp secure_compare(_, _), do: false
end
