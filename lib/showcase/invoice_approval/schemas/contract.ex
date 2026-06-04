defmodule Showcase.InvoiceApproval.Schemas.Contract do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.{Client, DocumentBundle}

  schema "ia_contracts" do
    field :name, :string
    field :body, :map, default: %{}
    field :default_thresholds, :map, default: %{}
    field :valid_from, :date
    field :valid_until, :date

    belongs_to :client, Client, foreign_key: :client_id
    has_many :document_bundles, DocumentBundle, foreign_key: :contract_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(contract, attrs) do
    contract
    |> cast(attrs, [:client_id, :name, :body, :default_thresholds, :valid_from, :valid_until])
    |> validate_required([:client_id, :name])
  end
end
