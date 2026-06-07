defmodule Showcase.OrderFlow.Schemas.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Client, OrderLine, SyntheticMessage}

  schema "of_orders" do
    field :status, :string, default: "pending_review"

    belongs_to :client, Client, foreign_key: :client_id
    belongs_to :synthetic_message, SyntheticMessage, foreign_key: :synthetic_message_id
    has_many :lines, OrderLine, foreign_key: :order_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:client_id, :status, :synthetic_message_id])
    |> validate_inclusion(:status, [
      "pending_review",
      "needs_client",
      "approved",
      "rejected",
      "sent_to_erp"
    ])
  end
end
