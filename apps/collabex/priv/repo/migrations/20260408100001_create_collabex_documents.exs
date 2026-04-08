defmodule CollabEx.Repo.Migrations.CreateCollabexDocuments do
  use Ecto.Migration

  def change do
    create table(:collabex_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, :string, null: false
      add :state, :binary
      add :update_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:collabex_documents, [:room_id])

    create table(:collabex_document_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, :string, null: false
      add :data, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:collabex_document_updates, [:room_id, :inserted_at])
  end
end
