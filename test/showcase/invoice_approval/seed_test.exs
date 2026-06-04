defmodule Showcase.InvoiceApproval.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.InvoiceApproval.Seed
  alias Showcase.Repo

  test "name/0 returns 'Invoice Approval'" do
    assert Seed.name() == "Invoice Approval"
  end

  test "description/0 returns value-framing copy" do
    desc = Seed.description()
    assert is_binary(desc)
    assert String.length(desc) > 20
  end

  test "oban_queue/0 returns :invoice_approval" do
    assert Seed.oban_queue() == :invoice_approval
  end

  test "tables/0 returns ia_* tables children-before-parents" do
    tables = Seed.tables()
    assert "ia_verdicts" in tables
    assert "ia_document_bundles" in tables
    assert "ia_contracts" in tables
    assert "ia_clients" in tables
    assert Enum.find_index(tables, &(&1 == "ia_verdicts")) <
             Enum.find_index(tables, &(&1 == "ia_document_bundles"))
  end

  test "seed/0 populates clients, contracts, bundles" do
    assert :ok = Seed.seed()
    assert Repo.aggregate(Client, :count) >= 3
    assert Repo.aggregate(Contract, :count) >= 3
    assert Repo.aggregate(DocumentBundle, :count) >= 4
  end

  test "seed/0 is idempotent" do
    assert :ok = Seed.seed()
    counts_a = {Repo.aggregate(Client, :count), Repo.aggregate(Contract, :count), Repo.aggregate(DocumentBundle, :count)}
    assert :ok = Seed.seed()
    counts_b = {Repo.aggregate(Client, :count), Repo.aggregate(Contract, :count), Repo.aggregate(DocumentBundle, :count)}
    assert counts_a == counts_b
  end
end
