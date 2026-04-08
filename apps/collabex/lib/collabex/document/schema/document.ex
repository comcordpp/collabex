defmodule CollabEx.Document.Schema.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "collabex_documents" do
    field :room_id, :string
    field :state, :binary
    field :update_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:room_id, :state, :update_count])
    |> validate_required([:room_id])
    |> unique_constraint(:room_id)
  end
end
