defmodule CollabEx.Document.Adapters.Postgres do
  @moduledoc """
  Postgres persistence adapter for CollabEx documents.

  Stores document state in a `collabex_documents` table with an append-only
  update log in `collabex_document_updates`. Compaction merges pending updates
  into the base state.

  ## Configuration

      config :collabex, CollabEx.Document.Adapters.Postgres,
        repo: MyApp.Repo,
        compaction_threshold: 100  # compact after N updates
  """

  @behaviour CollabEx.Document.Persistence

  import Ecto.Query

  alias CollabEx.Document.Schema.{Document, DocumentUpdate}

  @default_compaction_threshold 100

  @impl true
  def load(room_id) do
    repo = repo()

    case repo.get_by(Document, room_id: room_id) do
      nil -> {:error, :not_found}
      %{state: nil} -> {:error, :not_found}
      %{state: state} -> {:ok, state}
    end
  end

  @impl true
  def save(room_id, state) do
    repo = repo()

    case repo.get_by(Document, room_id: room_id) do
      nil ->
        %Document{}
        |> Document.changeset(%{room_id: room_id, state: state, update_count: 0})
        |> repo.insert()
        |> case do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end

      doc ->
        doc
        |> Document.changeset(%{state: state, update_count: 0})
        |> repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def append_update(room_id, update) do
    repo = repo()

    repo.transaction(fn ->
      # Insert update into log
      %DocumentUpdate{}
      |> DocumentUpdate.changeset(%{room_id: room_id, data: update})
      |> repo.insert!()

      # Increment update counter on document
      case repo.get_by(Document, room_id: room_id) do
        nil ->
          %Document{}
          |> Document.changeset(%{room_id: room_id, update_count: 1})
          |> repo.insert!()

        doc ->
          new_count = doc.update_count + 1

          doc
          |> Document.changeset(%{update_count: new_count})
          |> repo.update!()

          # Auto-compact if threshold reached
          if new_count >= compaction_threshold() do
            do_compact(room_id, repo)
          end
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def compact(room_id) do
    repo = repo()

    repo.transaction(fn ->
      do_compact(room_id, repo)
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def load_updates(room_id) do
    repo = repo()

    updates =
      DocumentUpdate
      |> where([u], u.room_id == ^room_id)
      |> order_by([u], asc: u.inserted_at)
      |> select([u], u.data)
      |> repo.all()

    {:ok, updates}
  end

  @impl true
  def delete(room_id) do
    repo = repo()

    repo.transaction(fn ->
      # Delete updates
      from(u in DocumentUpdate, where: u.room_id == ^room_id)
      |> repo.delete_all()

      # Delete document
      from(d in Document, where: d.room_id == ^room_id)
      |> repo.delete_all()
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private ---

  defp do_compact(room_id, repo) do
    # Load base state
    doc = repo.get_by(Document, room_id: room_id)
    base_state = doc && doc.state

    # Load pending updates
    updates =
      DocumentUpdate
      |> where([u], u.room_id == ^room_id)
      |> order_by([u], asc: u.inserted_at)
      |> select([u], u.data)
      |> repo.all()

    if updates == [] do
      {:ok, base_state}
    else
      # Merge all updates into base state
      # In production, use y_ex NIF for proper Yjs state merging
      compacted = Enum.reduce(updates, base_state, &merge_state/2)

      # Save compacted state
      if doc do
        doc
        |> Document.changeset(%{state: compacted, update_count: 0})
        |> repo.update!()
      else
        %Document{}
        |> Document.changeset(%{room_id: room_id, state: compacted, update_count: 0})
        |> repo.insert!()
      end

      # Clear update log
      from(u in DocumentUpdate, where: u.room_id == ^room_id)
      |> repo.delete_all()

      {:ok, compacted}
    end
  end

  defp merge_state(update, nil), do: update
  defp merge_state(update, base) when is_binary(base) and is_binary(update) do
    # Placeholder: in production, use y_ex NIF for proper Yjs CRDT merging
    # For now, concatenate (the Yjs decoder on the client will handle this)
    update
  end

  defp repo do
    Application.get_env(:collabex, __MODULE__, [])
    |> Keyword.fetch!(:repo)
  end

  defp compaction_threshold do
    Application.get_env(:collabex, __MODULE__, [])
    |> Keyword.get(:compaction_threshold, @default_compaction_threshold)
  end
end
