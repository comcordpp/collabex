defmodule CollabEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Room name → PID registry
      {Registry, keys: :unique, name: CollabEx.RoomRegistry},
      # Dynamic supervisor for room processes
      {DynamicSupervisor, strategy: :one_for_one, name: CollabEx.RoomSupervisor},
      # Prometheus metrics exporter
      {TelemetryMetricsPrometheus.Core, metrics: CollabEx.Telemetry.metrics()}
    ]

    opts = [strategy: :one_for_one, name: CollabEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
