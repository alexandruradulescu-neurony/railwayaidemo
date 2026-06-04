defmodule Showcase.OrderFlow.Schemas.ProductAlias do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Client, Product}

  schema "of_product_aliases" do
    field :normalized_text, :string
    field :confidence, :float, default: 0.5
    field :last_used_at, :utc_datetime_usec
    field :use_count, :integer, default: 1
    field :source, :string

    belongs_to :product, Product, foreign_key: :product_id
    belongs_to :client, Client, foreign_key: :client_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(alias_struct, attrs) do
    alias_struct
    |> cast(attrs, [:normalized_text, :product_id, :client_id, :confidence,
                    :last_used_at, :use_count, :source])
    |> validate_required([:normalized_text, :product_id, :last_used_at, :source])
    |> validate_inclusion(:source, ["correction", "promotion", "seed"])
  end
end
