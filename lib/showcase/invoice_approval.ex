defmodule Showcase.InvoiceApproval do
  @moduledoc """
  Public context for the Invoice Approval demo.

  Mirrors OrderFlow's pattern: LiveViews call into this context for all
  CRUD + workflow operations, the Pipeline/Worker pair handles async
  analysis, and verdicts get persisted with a status update on the bundle.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle, Verdict}
  alias Showcase.InvoiceApproval.Worker
  alias Showcase.Repo

  @upload_dir "priv/static/uploads/invoice_approval"
  @upload_url_prefix "/uploads/invoice_approval"

  # ── Clients ───────────────────────────────────────────────────────────

  @doc "All clients, alphabetically."
  def list_clients do
    Repo.all(from c in Client, order_by: c.name)
  end

  @doc "Find a client by exact email match. Used by the compose flow to map sender → record."
  def find_client_by_email(email) when is_binary(email) do
    Repo.get_by(Client, email: email)
  end

  def find_client_by_email(_), do: nil

  @doc "Find a client's most recent contract."
  def latest_contract_for(client_id) when is_integer(client_id) do
    Repo.one(
      from c in Contract,
        where: c.client_id == ^client_id,
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  # ── Bundles ───────────────────────────────────────────────────────────

  @doc "All bundles, newest first, with associations preloaded for list display."
  def list_bundles do
    Repo.all(
      from b in DocumentBundle,
        order_by: [desc: b.inserted_at],
        preload: [:client, :contract]
    )
  end

  @doc "Find a bundle by id with its verdict history."
  def find_bundle(id) do
    bundle = Repo.get(DocumentBundle, id) |> Repo.preload([:client, :contract])
    if bundle, do: %{bundle: bundle, verdicts: list_verdicts(bundle.id)}, else: nil
  end

  @doc "Fetch a bundle without the verdicts (cheaper)."
  def get_bundle!(id), do: Repo.get!(DocumentBundle, id) |> Repo.preload([:client, :contract])

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

  # Map demo clients to a canonical scenario so composed bundles inherit
  # rich invoice + aviz data (the AE attaches the matching PDFs but the
  # structured matching uses these predictable line items so the verdict
  # is reliable on stage).
  @client_to_scenario %{
    "Meesenburg Romania" => "clean_match",
    "Alexandru Erdei" => "price_drift",
    "Dragos Manolache" => "qty_mismatch"
  }

  defp demo_scenario_for(client_name), do: Map.get(@client_to_scenario, client_name)

  @doc """
  Compose a brand-new bundle from a "received" invoice email:
    * map the sender email → client
    * pull the client's contract + the demo scenario for that client so the
      invoice JSONB is pre-filled with realistic line items (matches the
      PDF the AE just attached)
    * stash the invoice attachment path
    * insert a bundle in "needs_aviz" status (waiting for the AP clerk to
      upload the aviz on the bundle detail).
  """
  @spec create_bundle_from_invoice(%{
          from_email: String.t(),
          subject: String.t() | nil,
          body: String.t() | nil,
          invoice_path: String.t() | nil
        }) :: {:ok, DocumentBundle.t()} | {:error, term()}
  def create_bundle_from_invoice(%{from_email: from_email} = attrs) do
    case find_client_by_email(from_email) do
      nil ->
        {:error, {:unknown_client, from_email}}

      %Client{} = client ->
        contract = latest_contract_for(client.id)
        scenario_name = demo_scenario_for(client.name)
        scenario_data = scenario_name && MockPrompts.find_scenario(scenario_name)

        invoice_jsonb =
          case scenario_data do
            nil ->
              %{
                "invoice_number" => Map.get(attrs, :subject, "F-?"),
                "issue_date" => Date.utc_today() |> Date.to_iso8601(),
                "items" => []
              }

            s ->
              # Override the invoice number with whatever the AE typed in
              # the Subject line (otherwise we'd reuse the canned number).
              Map.put(s.invoice, "invoice_number", Map.get(attrs, :subject) || s.invoice["invoice_number"])
          end

        thresholds =
          (scenario_data && scenario_data.thresholds) ||
            (contract && contract.default_thresholds) ||
            %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3}

        bundle =
          %DocumentBundle{}
          |> DocumentBundle.changeset(%{
            client_id: client.id,
            contract_id: contract && contract.id,
            # Use the canonical scenario name so the pipeline's scripted
            # lookup hits the right response.
            scenario: scenario_name || "composed_#{System.unique_integer([:positive])}",
            kind: "composed",
            status: "needs_aviz",
            invoice: invoice_jsonb,
            invoice_path: Map.get(attrs, :invoice_path),
            thresholds: thresholds,
            composed: true
          })
          |> Repo.insert!()
          |> Repo.preload([:client, :contract])

        {:ok, bundle}
    end
  end

  @doc """
  Attach an uploaded aviz file to a bundle, pre-fill `delivery_notes` from
  the client's demo scenario (so the 3-way matrix has data to work with),
  and re-enqueue analysis. Returns the updated bundle.
  """
  @spec attach_aviz(integer() | DocumentBundle.t(), String.t()) ::
          {:ok, DocumentBundle.t()} | {:error, term()}
  def attach_aviz(%DocumentBundle{} = bundle, aviz_path) when is_binary(aviz_path) do
    bundle = Repo.preload(bundle, [:client, :contract])
    scenario_name = bundle.client && demo_scenario_for(bundle.client.name)
    scenario_data = scenario_name && MockPrompts.find_scenario(scenario_name)

    delivery_jsonb =
      case scenario_data do
        # No demo mapping → keep whatever's already there (may be empty)
        nil -> bundle.delivery_notes
        s -> s.delivery_notes
      end

    {:ok, updated} =
      bundle
      |> DocumentBundle.changeset(%{
        aviz_path: aviz_path,
        delivery_notes: delivery_jsonb,
        status: "analyzing"
      })
      |> Repo.update()

    {:ok, _job} = enqueue(updated.id)
    {:ok, Repo.preload(updated, [:client, :contract], force: true)}
  end

  def attach_aviz(id, aviz_path) when is_integer(id) do
    case Repo.get(DocumentBundle, id) do
      nil -> {:error, :not_found}
      bundle -> attach_aviz(bundle, aviz_path)
    end
  end

  @doc "Persist an uploaded file under the invoice_approval uploads dir."
  @spec save_attachment(Path.t(), String.t()) :: String.t()
  def save_attachment(temp_path, original_name) do
    File.mkdir_p!(@upload_dir)
    ext = original_name |> Path.extname() |> String.downcase()
    filename = "#{System.unique_integer([:positive])}-#{:erlang.unique_integer([:positive])}#{ext}"
    dest = Path.join(@upload_dir, filename)
    File.cp!(temp_path, dest)
    "#{@upload_url_prefix}/#{filename}"
  end

  @doc "Delete a bundle (and its uploaded files)."
  def delete_bundle(%DocumentBundle{} = bundle) do
    Enum.each([bundle.invoice_path, bundle.aviz_path], &delete_upload/1)
    Repo.delete_all(from v in Verdict, where: v.bundle_id == ^bundle.id)
    Repo.delete(bundle)
  end

  def delete_bundle(id) when is_integer(id) do
    case Repo.get(DocumentBundle, id) do
      nil -> {:error, :not_found}
      bundle -> delete_bundle(bundle)
    end
  end

  defp delete_upload(path) when is_binary(path) do
    File.rm(Path.join("priv/static", String.trim_leading(path, "/")))
  end

  defp delete_upload(_), do: :ok

  # ── ERP submission (mirror of OrderFlow) ──────────────────────────────

  @doc "Mark a bundle as sent to ERP."
  @spec mark_sent_to_erp(DocumentBundle.t() | integer()) ::
          {:ok, DocumentBundle.t()} | {:error, term()}
  def mark_sent_to_erp(%DocumentBundle{} = bundle) do
    bundle
    |> DocumentBundle.changeset(%{status: "sent_to_erp"})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, [:client, :contract], force: true)}
      err -> err
    end
  end

  def mark_sent_to_erp(id) when is_integer(id) do
    case Repo.get(DocumentBundle, id) do
      nil -> {:error, :not_found}
      b -> mark_sent_to_erp(b)
    end
  end

  @doc "Generate a fake ERP reference for the demo's 'sent to ERP' confirmation."
  @spec erp_reference(DocumentBundle.t() | integer()) :: String.t()
  def erp_reference(%DocumentBundle{id: id}), do: erp_reference(id)

  def erp_reference(id) when is_integer(id) do
    "AP-2026-#{:io_lib.format("~6..0B", [id]) |> List.to_string()}"
  end

  # ── Status derivation for inbox badges ────────────────────────────────

  @doc """
  Effective status of a bundle for inbox display. Considers both the
  stored `status` field and the latest verdict's outcome.
  """
  @spec effective_status(DocumentBundle.t()) :: String.t()
  def effective_status(%DocumentBundle{status: "sent_to_erp"}), do: "sent_to_erp"
  def effective_status(%DocumentBundle{status: "needs_aviz"}), do: "needs_aviz"
  def effective_status(%DocumentBundle{status: "analyzing"}), do: "analyzing"

  def effective_status(%DocumentBundle{} = bundle) do
    case latest_verdict(bundle.id) do
      nil -> "pending"
      %Verdict{outcome: outcome} -> outcome
    end
  end

  # ── Mocks ─────────────────────────────────────────────────────────────

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
