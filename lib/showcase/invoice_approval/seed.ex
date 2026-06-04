defmodule Showcase.InvoiceApproval.Seed do
  @moduledoc """
  Seeds the Invoice Approval demo with clients, contracts, and
  document bundles for each `MockPrompts.scenarios/0` entry.

  Idempotent.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.Repo

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
      seed_clients_and_contracts()
      seed_bundles()
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_clients_and_contracts do
    MockPrompts.scenarios()
    |> Enum.map(fn s -> {s.client_name, s.contract_name} end)
    |> Enum.uniq()
    |> Enum.each(fn {client_name, contract_name} ->
      client =
        case Repo.get_by(Client, name: client_name) do
          nil ->
            {:ok, c} = Repo.insert(%Client{name: client_name, contact: "ops@#{slug(client_name)}.example"})
            c
          existing -> existing
        end

      unless Repo.get_by(Contract, client_id: client.id, name: contract_name) do
        %Contract{}
        |> Contract.changeset(%{
          client_id: client.id,
          name: contract_name,
          body: %{"line_items" => []},
          default_thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
          valid_from: ~D[2026-01-01],
          valid_until: ~D[2026-12-31]
        })
        |> Repo.insert!()
      end
    end)
  end

  defp seed_bundles do
    Enum.each(MockPrompts.scenarios(), fn s ->
      client = Repo.get_by!(Client, name: s.client_name)
      contract = Repo.get_by!(Contract, client_id: client.id, name: s.contract_name)

      unless Repo.get_by(DocumentBundle, scenario: s.name) do
        %DocumentBundle{}
        |> DocumentBundle.changeset(%{
          client_id: client.id,
          contract_id: contract.id,
          scenario: s.name,
          kind: s.kind,
          delivery_notes: s.delivery_notes,
          invoice: s.invoice,
          thresholds: s.thresholds
        })
        |> Repo.insert!()
      end
    end)
  end

  defp slug(s) do
    s
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/[^a-z0-9\-]/, "")
  end
end
