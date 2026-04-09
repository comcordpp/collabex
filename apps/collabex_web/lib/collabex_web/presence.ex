defmodule CollabExWeb.Presence do
  @moduledoc """
  Phoenix Presence implementation for CollabEx room tracking.

  Tracks per-room user presence with metadata including name, color,
  and cursor position. Presence diffs are automatically broadcast to
  all participants in a room topic.

  ## Configuration

      config :collabex_web, CollabExWeb.Presence,
        disconnect_timeout: 30_000  # ms before presence is cleaned up (default: 30s)

  """

  use Phoenix.Presence,
    otp_app: :collabex_web,
    pubsub_server: CollabExWeb.PubSub

  @doc """
  Returns the configured disconnect timeout in milliseconds.
  Defaults to 30 seconds.
  """
  def disconnect_timeout do
    config = Application.get_env(:collabex_web, __MODULE__, [])
    Keyword.get(config, :disconnect_timeout, 30_000)
  end

  @doc """
  Fetches presence entries, merging all metas per key into a single map.
  Phoenix.Presence calls this automatically before broadcasting diffs.
  """
  def fetch(_topic, presences) do
    for {key, %{metas: metas}} <- presences, into: %{} do
      {key, %{metas: metas}}
    end
  end

  @doc """
  Lists all users present in a given room, formatted for API consumption.
  """
  def list_for_room(room_id) do
    "room:#{room_id}"
    |> list()
    |> Enum.map(fn {user_key, %{metas: metas}} ->
      # Take the most recent meta (last joined session)
      meta = List.last(metas) || %{}

      %{
        user_id: meta[:user_id] || user_key,
        client_id: meta[:client_id],
        name: meta[:name],
        color: meta[:color],
        cursor: meta[:cursor],
        online_at: meta[:online_at]
      }
    end)
  end
end
