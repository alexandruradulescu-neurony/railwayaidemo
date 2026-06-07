defmodule Showcase.InvoiceApproval.Schemas.Client do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ia_clients" do
    field :name, :string
    field :contact, :string
    field :email, :string
    field :vat_number, :string
    field :address, :string
    field :country, :string, default: "RO"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :contact, :email, :vat_number, :address, :country])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> unique_constraint(:email)
  end
end
