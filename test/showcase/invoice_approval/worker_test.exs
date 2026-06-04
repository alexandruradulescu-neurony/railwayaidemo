defmodule Showcase.InvoiceApproval.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.InvoiceApproval.Worker
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, client} = Repo.insert(%Client{name: "Acme Industries"})
    {:ok, contract} =
      %Contract{}
      |> Contract.changeset(%{client_id: client.id, name: "Test"})
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

    Mock.register("invoice_approval:verdict:v1",
      scenario: clean.name,
      text: clean.claude_response
    )

    {:ok, %{bundle: bundle}}
  end

  test "perform/1 returns :ok for a known bundle", %{bundle: bundle} do
    assert :ok = perform_job(Worker, %{"bundle_id" => bundle.id})
  end

  test "perform/1 returns {:error, :not_found} for unknown bundle id" do
    assert {:error, :not_found} = perform_job(Worker, %{"bundle_id" => 999_999})
  end

  test "Worker is on :invoice_approval queue" do
    assert Worker.__opts__()[:queue] == :invoice_approval
  end
end
