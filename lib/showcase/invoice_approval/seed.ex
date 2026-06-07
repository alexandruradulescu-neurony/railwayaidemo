defmodule Showcase.InvoiceApproval.Seed do
  @moduledoc """
  Seeds the Invoice Approval demo with Meesenburg-style Romanian feronerie
  clients, real contracts (with PDF-renderable line items), and document
  bundles where each has invoice + aviz already populated so the demo
  inbox shows pre-analyzed verdicts on first load.

  Idempotent.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.Repo

  # Match the shared client directory used by OrderFlow + Restaurant Compliance
  # so the demo tells one coherent story across all five demos.
  @clients [
    %{
      name: "Meesenburg Romania",
      email: "comenzi@meesenburg.ro",
      contact: "Comenzi Meesenburg",
      vat_number: "RO12345678",
      address: "Str. Industriei nr. 12, București, Sector 3",
      country: "RO"
    },
    %{
      name: "Alexandru Erdei",
      email: "alexandru.erdei@meesenburg.ro",
      contact: "Alexandru Erdei",
      vat_number: "RO12345678",
      address: "Str. Industriei nr. 12, București, Sector 3",
      country: "RO"
    },
    %{
      name: "Dragos Manolache",
      email: "dragosimcom@gmail.com",
      contact: "Dragos Manolache",
      vat_number: "RO87654321",
      address: "Str. Avram Iancu nr. 5, Cluj-Napoca",
      country: "RO"
    }
  ]

  @impl true
  def name, do: "Invoice Approval"

  @impl true
  def description do
    "Three-way matching of contract, delivery note, and invoice. Configurable thresholds; explainable verdicts; override + audit-trail loop."
  end

  @impl true
  def oban_queue, do: :invoice_approval

  @impl true
  def tables do
    ["ia_verdicts", "ia_document_bundles", "ia_contracts", "ia_clients"]
  end

  @impl true
  def seed do
    Repo.transaction(fn ->
      seed_clients()
      seed_contracts_and_bundles()
    end)
    |> case do
      {:ok, _} ->
        seed_system_prompts()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "invoice_approval",
      "approval",
      Showcase.InvoiceApproval.Pipeline.system_prompt(),
      note: "3-way matches contract + delivery notes + invoice, returns verdict."
    )
  end

  defp seed_clients do
    Enum.each(@clients, fn attrs ->
      %Client{}
      |> Client.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
    end)
  end

  defp seed_contracts_and_bundles do
    # Group scenarios by their (client, contract) tuple — multiple bundles
    # can share the same contract (e.g. clean_match + out_of_contract both
    # use Meesenburg's "Contract-cadru feronerie 2026").
    by_contract =
      MockPrompts.scenarios()
      |> Enum.group_by(fn s -> {s.client_name, s.contract_name} end)

    Enum.each(by_contract, fn {{client_name, contract_name}, scenarios} ->
      client = Repo.get_by!(Client, name: client_name)
      # The first scenario for this contract supplies its line items.
      first = hd(scenarios)

      contract =
        case Repo.get_by(Contract, client_id: client.id, name: contract_name) do
          nil ->
            %Contract{}
            |> Contract.changeset(%{
              client_id: client.id,
              name: contract_name,
              body: %{"line_items" => first.contract_items},
              default_thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
              valid_from: ~D[2026-01-01],
              valid_until: ~D[2026-12-31],
              contract_number: "CTR-2026-#{:io_lib.format("~4..0B", [:erlang.phash2(contract_name, 10_000)]) |> List.to_string()}",
              currency: "RON"
            })
            |> Repo.insert!()

          existing ->
            existing
        end

      Enum.each(scenarios, fn s ->
        unless Repo.get_by(DocumentBundle, scenario: s.name) do
          %DocumentBundle{}
          |> DocumentBundle.changeset(%{
            client_id: client.id,
            contract_id: contract.id,
            scenario: s.name,
            kind: s.kind,
            delivery_notes: s.delivery_notes,
            invoice: s.invoice,
            thresholds: s.thresholds,
            status: "pending",
            composed: false
          })
          |> Repo.insert!()
        end
      end)
    end)
  end
end
