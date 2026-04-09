defmodule CollabEx.Room.Server do
  @moduledoc """
  GenServer representing a single collaboration room.

  Each room_id spawns a dedicated process via DynamicSupervisor. The room:
  - Holds the Yjs document state in memory (binary encoding)
  - Tracks connected clients
  - Hibernates after configurable idle timeout (default 5 min)
  - Terminates after configurable empty timeout (default 30 min with no clients)
  - Recovers state from persistence adapter on restart
  - Emits telemetry events for monitoring
  """
  use GenServer, restart: :transient

  alias CollabEx.Telemetry, as: Tel

  require Logger

  @default_idle_timeout_ms :timer.minutes(5)
  @default_empty_timeout_ms :timer.minutes(30)

  defstruct [
    :room_id,
    :document_state,
    :persistence_adapter,
    :idle_timeout_ms,
    :empty_timeout_ms,
    clients: %{},
    last_activity_at: nil,
    created_at: nil
  ]

  # --- Client API ---

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  @doc "Registry-based name lookup."
  def via(room_id) do
    {:via, Registry, {CollabEx.RoomRegistry, room_id}}
  end

  @doc "Get the current document state."
  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  end

  @doc "Apply a Yjs update to the document."
  def apply_update(room_id, update, client_id) do
    GenServer.call(via(room_id), {:apply_update, update, client_id})
  end

  @doc "Register a client connection with optional auth context."
  def join(room_id, client_id, client_pid, auth_context \\ %{}) do
    GenServer.call(via(room_id), {:join, client_id, client_pid, auth_context})
  end

  @doc "Unregister a client connection."
  def leave(room_id, client_id) do
    GenServer.cast(via(room_id), {:leave, client_id})
  end

  @doc "Get connected client count."
  def client_count(room_id) do
    GenServer.call(via(room_id), :client_count)
  end

  @doc "Get auth context for a specific client."
  def get_client_auth(room_id, client_id) do
    GenServer.call(via(room_id), {:get_client_auth, client_id})
  end

  @doc "Get room info for debugging/monitoring."
  def info(room_id) do
    GenServer.call(via(room_id), :info)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    persistence = Keyword.get(opts, :persistence_adapter)
    idle_timeout = Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms)
    empty_timeout = Keyword.get(opts, :empty_timeout_ms, @default_empty_timeout_ms)

    # Recover state from persistence if available
    document_state = recover_state(room_id, persistence)

    now = DateTime.utc_now()

    state = %__MODULE__{
      room_id: room_id,
      document_state: document_state,
      persistence_adapter: persistence,
      idle_timeout_ms: idle_timeout,
      empty_timeout_ms: empty_timeout,
      clients: %{},
      last_activity_at: now,
      created_at: now
    }

    Logger.info("Room #{room_id} started")
    Tel.room_created(room_id)

    # Start with empty timeout since no clients are connected yet
    {:ok, state, empty_timeout}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state.document_state}, state, timeout_for(state)}
  end

  @impl true
  def handle_call({:apply_update, update, client_id}, _from, state) do
    start_time = System.monotonic_time()

    # Merge update into document state
    new_doc_state = merge_update(state.document_state, update)
    new_state = %{state | document_state: new_doc_state, last_activity_at: DateTime.utc_now()}

    # Persist state if adapter is configured
    persist_state(new_state)

    # Broadcast update to other clients
    broadcast(state.clients, client_id, {:yjs_update, state.room_id, update})

    duration = System.monotonic_time() - start_time
    Tel.sync_message_processed(state.room_id, :update, duration)

    {:reply, :ok, new_state, timeout_for(new_state)}
  end

  @impl true
  def handle_call({:join, client_id, client_pid, auth_context}, _from, state) do
    # Monitor the client process for automatic cleanup on disconnect
    ref = Process.monitor(client_pid)

    new_clients =
      Map.put(state.clients, client_id, %{
        pid: client_pid,
        ref: ref,
        user_id: Map.get(auth_context, :user_id),
        permissions: Map.get(auth_context, :permissions, []),
        auth_context: auth_context
      })

    new_state = %{state | clients: new_clients, last_activity_at: DateTime.utc_now()}

    Logger.debug("Client #{client_id} joined room #{state.room_id} (#{map_size(new_clients)} clients)")
    Tel.client_connected(state.room_id, client_id, map_size(new_clients))

    {:reply, {:ok, state.document_state}, new_state, timeout_for(new_state)}
  end

  @impl true
  def handle_call({:get_client_auth, client_id}, _from, state) do
    result =
      case Map.get(state.clients, client_id) do
        %{auth_context: auth_context} -> {:ok, auth_context}
        nil -> {:error, :not_found}
      end

    {:reply, result, state, timeout_for(state)}
  end

  @impl true
  def handle_call(:client_count, _from, state) do
    {:reply, map_size(state.clients), state, timeout_for(state)}
  end

  @impl true
  def handle_call(:info, _from, state) do
    doc_bytes = byte_size(state.document_state || <<>>)
    Tel.room_memory(state.room_id, doc_bytes)

    info = %{
      room_id: state.room_id,
      client_count: map_size(state.clients),
      document_size: doc_bytes,
      created_at: state.created_at,
      last_activity_at: state.last_activity_at
    }

    {:reply, info, state, timeout_for(state)}
  end

  @impl true
  def handle_cast({:leave, client_id}, state) do
    new_state = remove_client(state, client_id)
    {:noreply, new_state, timeout_for(new_state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Find and remove the client whose process died
    client_entry =
      Enum.find(state.clients, fn {_id, %{pid: pid}} ->
        !Process.alive?(pid)
      end)

    new_state =
      case client_entry do
        {client_id, _} -> remove_client(state, client_id)
        nil -> state
      end

    {:noreply, new_state, timeout_for(new_state)}
  end

  @impl true
  def handle_info(:timeout, state) do
    if map_size(state.clients) == 0 do
      Logger.info("Room #{state.room_id} shutting down (empty timeout)")
      {:stop, {:shutdown, :empty_timeout}, state}
    else
      # Room has clients but was idle — hibernate to save memory
      Logger.debug("Room #{state.room_id} hibernating (idle timeout)")
      {:noreply, state, :hibernate}
    end
  end

  @impl true
  def handle_info(:hibernate, state) do
    {:noreply, state, :hibernate}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Room #{state.room_id} terminating: #{inspect(reason)}")
    persist_state(state)
    Tel.room_terminated(state.room_id, reason)
    :ok
  end

  # --- Private ---

  defp remove_client(state, client_id) do
    case Map.pop(state.clients, client_id) do
      {%{ref: ref}, new_clients} ->
        Process.demonitor(ref, [:flush])
        Logger.debug("Client #{client_id} left room #{state.room_id} (#{map_size(new_clients)} clients)")
        Tel.client_disconnected(state.room_id, client_id, map_size(new_clients))
        %{state | clients: new_clients}

      {nil, _} ->
        state
    end
  end

  defp timeout_for(state) do
    if map_size(state.clients) == 0 do
      state.empty_timeout_ms
    else
      state.idle_timeout_ms
    end
  end

  defp recover_state(room_id, nil), do: nil

  defp recover_state(room_id, adapter) do
    case adapter.load(room_id) do
      {:ok, state} ->
        Tel.document_loaded(room_id)
        state

      {:error, :not_found} ->
        nil

      {:error, reason} ->
        Logger.warning("Failed to recover room #{room_id}: #{inspect(reason)}")
        nil
    end
  end

  defp persist_state(%{persistence_adapter: nil}), do: :ok

  defp persist_state(%{persistence_adapter: adapter, room_id: room_id, document_state: doc_state})
       when not is_nil(doc_state) do
    {result, duration} =
      Tel.span(fn ->
        adapter.save(room_id, doc_state)
      end)

    case result do
      :ok ->
        Tel.document_persisted(room_id, duration)
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist room #{room_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp persist_state(_), do: :ok

  defp merge_update(nil, update), do: update
  defp merge_update(current, update) when is_binary(current) and is_binary(update) do
    # In a real implementation, this would use y_ex NIF or similar Yjs library
    # For now, we store the latest state (updates are cumulative in Yjs protocol)
    update
  end

  defp broadcast(clients, sender_id, message) do
    Enum.each(clients, fn {client_id, %{pid: pid}} ->
      if client_id != sender_id do
        send(pid, message)
      end
    end)
  end
end
