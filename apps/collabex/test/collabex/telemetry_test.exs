defmodule CollabEx.TelemetryTest do
  use ExUnit.Case, async: true

  alias CollabEx.Telemetry, as: Tel

  describe "metrics/0" do
    test "returns a non-empty list of metric definitions" do
      metrics = Tel.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0
    end

    test "includes room count metric" do
      metrics = Tel.metrics()
      assert Enum.any?(metrics, &match?(%Telemetry.Metrics.LastValue{name: "collabex.room.count" <> _}, &1))
    end

    test "includes sync duration metric" do
      metrics = Tel.metrics()
      assert Enum.any?(metrics, &match?(%Telemetry.Metrics.Distribution{name: "collabex.sync.duration" <> _}, &1))
    end

    test "includes persistence duration metric" do
      metrics = Tel.metrics()
      assert Enum.any?(metrics, &match?(%Telemetry.Metrics.Distribution{name: "collabex.document.persist_duration" <> _}, &1))
    end
  end

  describe "event emission" do
    setup do
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:collabex, :room, :created],
          [:collabex, :room, :terminated],
          [:collabex, :client, :connected],
          [:collabex, :client, :disconnected],
          [:collabex, :sync, :message_processed],
          [:collabex, :document, :persisted],
          [:collabex, :document, :loaded],
          [:collabex, :room, :memory]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "room_created emits event" do
      Tel.room_created("test-room")
      assert_receive {:telemetry_event, [:collabex, :room, :created], %{system_time: _}, %{room_id: "test-room"}}
    end

    test "room_terminated emits event with reason" do
      Tel.room_terminated("test-room", :empty_timeout)

      assert_receive {:telemetry_event, [:collabex, :room, :terminated], %{system_time: _},
                      %{room_id: "test-room", reason: :empty_timeout}}
    end

    test "client_connected emits event with count" do
      Tel.client_connected("test-room", "client-1", 3)

      assert_receive {:telemetry_event, [:collabex, :client, :connected], %{system_time: _, count: 3},
                      %{room_id: "test-room", client_id: "client-1"}}
    end

    test "client_disconnected emits event with count" do
      Tel.client_disconnected("test-room", "client-1", 2)

      assert_receive {:telemetry_event, [:collabex, :client, :disconnected], %{system_time: _, count: 2},
                      %{room_id: "test-room", client_id: "client-1"}}
    end

    test "sync_message_processed emits event with duration" do
      Tel.sync_message_processed("test-room", :update, 1234)

      assert_receive {:telemetry_event, [:collabex, :sync, :message_processed],
                      %{system_time: _, duration: 1234}, %{room_id: "test-room", message_type: :update}}
    end

    test "document_persisted emits event with duration" do
      Tel.document_persisted("test-room", 5678)

      assert_receive {:telemetry_event, [:collabex, :document, :persisted], %{system_time: _, duration: 5678},
                      %{room_id: "test-room"}}
    end

    test "document_loaded emits event" do
      Tel.document_loaded("test-room")
      assert_receive {:telemetry_event, [:collabex, :document, :loaded], %{system_time: _}, %{room_id: "test-room"}}
    end

    test "room_memory emits event with bytes" do
      Tel.room_memory("test-room", 4096)

      assert_receive {:telemetry_event, [:collabex, :room, :memory], %{bytes: 4096, system_time: _},
                      %{room_id: "test-room"}}
    end
  end

  describe "span/1" do
    test "returns result and duration" do
      {result, duration} = Tel.span(fn -> :hello end)
      assert result == :hello
      assert is_integer(duration)
      assert duration >= 0
    end

    test "duration reflects work done" do
      {_result, duration} = Tel.span(fn -> Process.sleep(10); :done end)
      # Duration should be at least 10ms in native units
      assert duration > 0
    end
  end
end
