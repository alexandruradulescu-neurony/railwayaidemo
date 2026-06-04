defmodule Showcase.InvoiceApproval.Schemas.Client do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ia_clients" do
    field :name, :string
    field :contact, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :contact])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
