defmodule Showcase.OrderFlow.Schemas.Client do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_clients" do
    field :name, :string
    field :email, :string
    field :phone, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :email, :phone])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
