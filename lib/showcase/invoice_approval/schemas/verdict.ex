defmodule Showcase.InvoiceApproval.Schemas.Verdict do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.DocumentBundle

  schema "ia_verdicts" do
    field :outcome, :string
    field :reasoning, :string
    field :raw_matrix, :map, default: %{}
    field :classified_matrix, :map, default: %{}
    field :thresholds_used, :map, default: %{}
    field :source, :string
    field :actor, :string

    belongs_to :bundle, DocumentBundle, foreign_key: :bundle_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @valid_outcomes ["approve", "reject", "needs_human"]
  @valid_sources ["ai", "override"]

  def changeset(verdict, attrs) do
    verdict
    |> cast(attrs, [:bundle_id, :outcome, :reasoning, :raw_matrix, :classified_matrix,
                    :thresholds_used, :source, :actor])
    |> validate_required([:bundle_id, :outcome, :reasoning, :source])
    |> validate_inclusion(:outcome, @valid_outcomes)
    |> validate_inclusion(:source, @valid_sources)
  end
end
