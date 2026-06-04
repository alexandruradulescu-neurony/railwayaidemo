defmodule Showcase.OrderFlow.Schemas.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_products" do
    field :sku, :string
    field :name, :string
    field :normalized_name, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku, :name, :normalized_name])
    |> validate_required([:sku, :name, :normalized_name])
    |> unique_constraint(:sku)
  end
end
