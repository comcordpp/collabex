defmodule CollabEx.AuthTest do
  use ExUnit.Case, async: true

  alias CollabEx.Auth

  defmodule PassMiddleware do
    @behaviour CollabEx.Auth.Middleware

    @impl true
    def authenticate(_params, context, opts) do
      key = Keyword.get(opts, :key, :passed)
      {:ok, Map.put(context, key, true)}
    end
  end

  defmodule FailMiddleware do
    @behaviour CollabEx.Auth.Middleware

    @impl true
    def authenticate(_params, _context, _opts) do
      {:error, :rejected}
    end
  end

  setup do
    # Store and restore original config
    original = Application.get_env(:collabex, CollabEx.Auth)
    on_exit(fn -> Application.put_env(:collabex, CollabEx.Auth, original || []) end)
    :ok
  end

  test "empty pipeline allows all connections" do
    Application.put_env(:collabex, CollabEx.Auth, pipeline: [])
    assert {:ok, %{}} = Auth.authenticate(%{"token" => "anything"})
  end

  test "pipeline passes context through middleware chain" do
    Application.put_env(:collabex, CollabEx.Auth,
      pipeline: [
        {PassMiddleware, key: :first},
        {PassMiddleware, key: :second}
      ]
    )

    assert {:ok, context} = Auth.authenticate(%{})
    assert context.first == true
    assert context.second == true
  end

  test "pipeline stops on first failure" do
    Application.put_env(:collabex, CollabEx.Auth,
      pipeline: [
        {PassMiddleware, key: :first},
        FailMiddleware,
        {PassMiddleware, key: :third}
      ]
    )

    assert {:error, :rejected} = Auth.authenticate(%{})
  end

  test "bare atom middleware works without opts" do
    Application.put_env(:collabex, CollabEx.Auth,
      pipeline: [PassMiddleware]
    )

    assert {:ok, %{passed: true}} = Auth.authenticate(%{})
  end

  test "initial context is passed through" do
    Application.put_env(:collabex, CollabEx.Auth, pipeline: [])
    assert {:ok, %{existing: "value"}} = Auth.authenticate(%{}, %{existing: "value"})
  end
end
