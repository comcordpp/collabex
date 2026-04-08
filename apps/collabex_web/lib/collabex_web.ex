defmodule CollabExWeb do
  @moduledoc """
  CollabExWeb — Phoenix web layer for CollabEx collaboration server.
  """

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
