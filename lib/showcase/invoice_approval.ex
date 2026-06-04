defmodule Showcase.InvoiceApproval do
  @moduledoc """
  Public context for the Invoice Approval demo.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{DocumentBundle, Verdict}
  alias Showcase.InvoiceApproval.Worker
  alias Showcase.Repo

  @doc "All seeded bundles, oldest first."
  def list_bundles do
    Repo.all(from b in DocumentBundle, order_by: [asc: b.id], preload: [:client, :contract])
  end

  @doc "Find a bundle by id with its verdict history."
  def find_bundle(id) do
    bundle = Repo.get(DocumentBundle, id) |> Repo.preload([:client, :contract])
    if bundle, do: %{bundle: bundle, verdicts: list_verdicts(bundle.id)}, else: nil
  end

  @doc "All verdicts for a bundle, latest first."
  def list_verdicts(bundle_id) do
    Repo.all(
      from v in Verdict,
        where: v.bundle_id == ^bundle_id,
        order_by: [desc: v.inserted_at]
    )
  end

  @doc "Latest verdict for a bundle, or nil."
  def latest_verdict(bundle_id) do
    Repo.one(
      from v in Verdict,
        where: v.bundle_id == ^bundle_id,
        order_by: [desc: v.inserted_at],
        limit: 1
    )
  end

  @doc "Enqueue an Oban job to process this bundle."
  def enqueue(bundle_id) when is_integer(bundle_id) do
    Worker.new(%{bundle_id: bundle_id}) |> Oban.insert()
  end

  @doc """
  Register Mock responses for every scenario in `MockPrompts.scenarios/0`.
  Idempotent — re-running just overwrites the same keys.
  """
  def register_mock_responses do
    Enum.each(MockPrompts.scenarios(), fn s ->
      Mock.register("invoice_approval:verdict:v1",
        scenario: s.name,
        text: s.claude_response
      )
    end)
  end

  @doc """
  Write a manual verdict override. Creates a new `Verdict` row with
  `source: "override"` AND an entry in `Showcase.Common.AuditLog`.
  """
  def override_verdict(bundle_id, outcome, reason, actor)
      when outcome in ["approve", "reject", "needs_human"] do
    case latest_verdict(bundle_id) do
      nil ->
        {:error, :no_prior_verdict}

      latest ->
        attrs = %{
          bundle_id: bundle_id,
          outcome: outcome,
          reasoning: "Override: #{reason}",
          raw_matrix: latest.raw_matrix,
          classified_matrix: latest.classified_matrix,
          thresholds_used: latest.thresholds_used,
          source: "override",
          actor: actor
        }

        Repo.transaction(fn ->
          {:ok, override} = %Verdict{} |> Verdict.changeset(attrs) |> Repo.insert()

          Showcase.Common.AuditLog
          |> Ash.Changeset.for_create(:write, %{
            demo: "invoice_approval",
            entity_type: "bundle",
            entity_id: to_string(bundle_id),
            event: "verdict_override",
            payload: %{
              from: latest.outcome,
              to: outcome,
              reason: reason
            },
            actor: actor
          })
          |> Ash.create()

          override
        end)
    end
  end
end
