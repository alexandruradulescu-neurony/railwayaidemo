defmodule Showcase.OrderFlow.Schemas.SyntheticMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_synthetic_messages" do
    field :body, :string
    field :kind, :string
    field :scenario, :string
    field :client_hint, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:body, :kind, :scenario, :client_hint])
    |> validate_required([:body, :kind, :scenario])
    |> validate_inclusion(:kind, ["email", "whatsapp"])
  end
end
