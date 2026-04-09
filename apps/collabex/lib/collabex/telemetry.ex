defmodule CollabEx.Telemetry do
  @moduledoc """
  Telemetry events and metric definitions for CollabEx.

  ## Events

  All events are prefixed with `[:collabex, ...]`.

  ### Room lifecycle
  - `[:collabex, :room, :created]` — room process started
  - `[:collabex, :room, :terminated]` — room process stopped

  ### Client connections
  - `[:collabex, :client, :connected]` — client joined a room
  - `[:collabex, :client, :disconnected]` — client left a room

  ### Sync protocol
  - `[:collabex, :sync, :message_processed]` — Yjs sync message handled

  ### Persistence
  - `[:collabex, :document, :persisted]` — document state saved to storage
  - `[:collabex, :document, :loaded]` — document state loaded from storage

  ## Measurements

  Each event includes at minimum a `:system_time` measurement. Events that
  involve work (sync, persistence) also include `:duration` in native units.

  ## Metadata

  All events include `:room_id`. Client events add `:client_id`. Sync events
  add `:message_type`.

  ## Prometheus Metrics

  Call `CollabEx.Telemetry.metrics/0` to get a list of `Telemetry.Metrics`
  structs suitable for a Prometheus exporter.
  """

  import Telemetry.Metrics

  @doc """
  Returns a list of telemetry metric definitions for Prometheus export.
  """
  def metrics do
    [
      # Room gauges
      last_value("collabex.room.count",
        description: "Number of active rooms",
        unit: {:native, :millisecond}
      ),

      # Connection gauges
      last_value("collabex.client.count",
        description: "Number of active client connections",
        unit: {:native, :millisecond}
      ),

      # Room lifecycle counters
      counter("collabex.room.created.total",
        event_name: [:collabex, :room, :created],
        description: "Total rooms created"
      ),

      counter("collabex.room.terminated.total",
        event_name: [:collabex, :room, :terminated],
        description: "Total rooms terminated"
      ),

      # Client connection counters
      counter("collabex.client.connected.total",
        event_name: [:collabex, :client, :connected],
        description: "Total client connections"
      ),

      counter("collabex.client.disconnected.total",
        event_name: [:collabex, :client, :disconnected],
        description: "Total client disconnections"
      ),

      # Sync latency histogram
      distribution("collabex.sync.duration",
        event_name: [:collabex, :sync, :message_processed],
        measurement: :duration,
        description: "Sync message processing time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [0.5, 1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),

      # Sync message counter by type
      counter("collabex.sync.message_processed.total",
        event_name: [:collabex, :sync, :message_processed],
        description: "Total sync messages processed",
        tags: [:message_type]
      ),

      # Persistence write histogram
      distribution("collabex.document.persist_duration",
        event_name: [:collabex, :document, :persisted],
        measurement: :duration,
        description: "Document persistence write time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000]]
      ),

      # Persistence counters
      counter("collabex.document.persisted.total",
        event_name: [:collabex, :document, :persisted],
        description: "Total document persist operations"
      ),

      counter("collabex.document.loaded.total",
        event_name: [:collabex, :document, :loaded],
        description: "Total document load operations"
      ),

      # Memory per room
      last_value("collabex.room.memory_bytes",
        event_name: [:collabex, :room, :memory],
        measurement: :bytes,
        description: "Memory usage per room in bytes",
        tags: [:room_id]
      )
    ]
  end

  @doc """
  Emits a room created event.
  """
  def room_created(room_id) do
    :telemetry.execute(
      [:collabex, :room, :created],
      %{system_time: System.system_time()},
      %{room_id: room_id}
    )
  end

  @doc """
  Emits a room terminated event.
  """
  def room_terminated(room_id, reason) do
    :telemetry.execute(
      [:collabex, :room, :terminated],
      %{system_time: System.system_time()},
      %{room_id: room_id, reason: reason}
    )
  end

  @doc """
  Emits a client connected event.
  """
  def client_connected(room_id, client_id, client_count) do
    :telemetry.execute(
      [:collabex, :client, :connected],
      %{system_time: System.system_time(), count: client_count},
      %{room_id: room_id, client_id: client_id}
    )
  end

  @doc """
  Emits a client disconnected event.
  """
  def client_disconnected(room_id, client_id, client_count) do
    :telemetry.execute(
      [:collabex, :client, :disconnected],
      %{system_time: System.system_time(), count: client_count},
      %{room_id: room_id, client_id: client_id}
    )
  end

  @doc """
  Emits a sync message processed event with duration measurement.
  """
  def sync_message_processed(room_id, message_type, duration) do
    :telemetry.execute(
      [:collabex, :sync, :message_processed],
      %{system_time: System.system_time(), duration: duration},
      %{room_id: room_id, message_type: message_type}
    )
  end

  @doc """
  Emits a document persisted event with duration measurement.
  """
  def document_persisted(room_id, duration) do
    :telemetry.execute(
      [:collabex, :document, :persisted],
      %{system_time: System.system_time(), duration: duration},
      %{room_id: room_id}
    )
  end

  @doc """
  Emits a document loaded event.
  """
  def document_loaded(room_id) do
    :telemetry.execute(
      [:collabex, :document, :loaded],
      %{system_time: System.system_time()},
      %{room_id: room_id}
    )
  end

  @doc """
  Emits a room memory measurement.
  """
  def room_memory(room_id, bytes) do
    :telemetry.execute(
      [:collabex, :room, :memory],
      %{bytes: bytes, system_time: System.system_time()},
      %{room_id: room_id}
    )
  end

  @doc """
  Measures the duration of a function call and returns its result.
  Duration is in native time units.
  """
  def span(fun) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start
    {result, duration}
  end
end
