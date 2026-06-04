defmodule Showcase.InvoiceApproval.Schemas.DocumentBundle do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, Verdict}

  schema "ia_document_bundles" do
    field :scenario, :string
    field :kind, :string
    field :delivery_notes, :map, default: %{}
    field :invoice, :map, default: %{}
    field :thresholds, :map, default: %{}

    belongs_to :client, Client, foreign_key: :client_id
    belongs_to :contract, Contract, foreign_key: :contract_id
    has_many :verdicts, Verdict, foreign_key: :bundle_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [:client_id, :contract_id, :scenario, :kind, :delivery_notes, :invoice, :thresholds])
    |> validate_required([:scenario, :kind])
  end
end
