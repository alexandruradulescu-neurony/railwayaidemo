defmodule Showcase.OrderFlow.Schemas.OrderLine do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Order, Product}

  schema "of_order_lines" do
    field :raw_description, :string
    field :quantity, :integer
    field :confidence, :float
    field :match_step, :string

    belongs_to :order, Order, foreign_key: :order_id
    belongs_to :product, Product, foreign_key: :product_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:order_id, :product_id, :raw_description, :quantity,
                    :confidence, :match_step])
    |> validate_required([:order_id, :raw_description, :quantity])
  end
end
