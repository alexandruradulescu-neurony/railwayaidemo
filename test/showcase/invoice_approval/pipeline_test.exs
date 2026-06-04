defmodule Showcase.InvoiceApproval.PipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Pipeline
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle, Verdict}
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, client} = Repo.insert(%Client{name: "Acme Industries"})
    {:ok, contract} =
      %Contract{}
      |> Contract.changeset(%{
        client_id: client.id,
        name: "Q2 2026 Hardware Order",
        body: %{},
        default_thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3}
      })
      |> Repo.insert()

    clean = Enum.find(MockPrompts.scenarios(), &(&1.name == "clean_match"))

    {:ok, bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: clean.name,
        kind: clean.kind,
        delivery_notes: clean.delivery_notes,
        invoice: clean.invoice,
        thresholds: clean.thresholds
      })
      |> Repo.insert()

    Mock.register(
      "invoice_approval:verdict:v1",
      scenario: clean.name,
      text: clean.claude_response
    )

    {:ok, %{client: client, contract: contract, bundle: bundle, scenario: clean}}
  end

  defp ctx, do: %{now: DateTime.utc_now()}

  test "process_bundle/2 returns an approved Verdict for a clean scenario",
       %{bundle: bundle} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "invoice_approval:processing:#{bundle.id}")

    {:ok, %Verdict{} = verdict} = Pipeline.process_bundle(bundle, ctx())

    assert verdict.bundle_id == bundle.id
    assert verdict.outcome == "approve"
    assert verdict.source == "ai"
    assert is_binary(verdict.reasoning)

    assert_received {:invoice_approval, :claude_returned, %{summary: _}}
    assert_received {:invoice_approval, :verdict_created, %{verdict_id: _, outcome: "approve"}}
  end

  test "process_bundle/2 returns a reject Verdict for an out-of-contract scenario",
       %{client: client, contract: contract} do
    ooc = Enum.find(MockPrompts.scenarios(), &(&1.name == "out_of_contract"))

    {:ok, bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: ooc.name,
        kind: ooc.kind,
        delivery_notes: ooc.delivery_notes,
        invoice: ooc.invoice,
        thresholds: ooc.thresholds
      })
      |> Repo.insert()

    Mock.register(
      "invoice_approval:verdict:v1",
      scenario: ooc.name,
      text: ooc.claude_response
    )

    {:ok, verdict} = Pipeline.process_bundle(bundle, ctx())
    assert verdict.outcome == "reject"
    assert verdict.reasoning =~ "EXTRA-99"
  end

  test "process_bundle/2 returns error when AnthropicClient fails (no Mock registered)",
       %{client: client, contract: contract} do
    {:ok, orphan_bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: "unregistered_scenario",
        kind: "clean",
        delivery_notes: %{"items" => []},
        invoice: %{"items" => []},
        thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3}
      })
      |> Repo.insert()

    assert {:error, _} = Pipeline.process_bundle(orphan_bundle, ctx())
  end
end
