defmodule CollabEx.Document.Schema.DocumentUpdate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "collabex_document_updates" do
    field :room_id, :string
    field :data, :binary

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(update, attrs) do
    update
    |> cast(attrs, [:room_id, :data])
    |> validate_required([:room_id, :data])
  end
end
