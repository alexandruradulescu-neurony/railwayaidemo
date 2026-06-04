defmodule Showcase.OrderFlow.Cascade.ClientAliasStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.ClientAliasStep
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias}
  alias Showcase.Repo

  @now ~U[2026-06-04 12:00:00.000000Z]

  setup do
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})
    {:ok, gasket} =
      %Product{}
      |> Product.changeset(%{sku: "GSK-4MM", name: "4mm Gasket", normalized_name: "4mm gasket"})
      |> Repo.insert()

    {:ok, %{client: client, gasket: gasket}}
  end

  defp ctx(client_id),
    do: %{repo: Repo, now: @now, client_id: client_id}

  test "returns match when client-scoped alias exists and is fresh",
       %{client: client, gasket: gasket} do
    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: one_month_ago,
        source: "correction"
      })
      |> Repo.insert()

    {:match, found, score} = ClientAliasStep.try_match("The 4mm Gaskets", ctx(client.id))
    assert found.id == gasket.id
    assert score == 0.85
  end

  test "ignores aliases from other clients",
       %{client: client, gasket: gasket} do
    {:ok, other} = Repo.insert(%Client{name: "Beta Corp"})
    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: other.id,
        confidence: 0.85,
        last_used_at: one_month_ago,
        source: "correction"
      })
      |> Repo.insert()

    assert ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id)) == :no_match
  end

  test "filters out expired aliases",
       %{client: client, gasket: gasket} do
    over_a_year_ago = DateTime.add(@now, -400, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: over_a_year_ago,
        source: "correction"
      })
      |> Repo.insert()

    assert ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id)) == :no_match
  end

  test "decays confidence between 6 and 12 months",
       %{client: client, gasket: gasket} do
    nine_months_ago = DateTime.add(@now, -270, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: nine_months_ago,
        source: "correction"
      })
      |> Repo.insert()

    {:match, _found, decayed} = ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id))
    assert decayed < 0.85
    assert decayed > 0.1
  end

  test "no_match when client_id is nil" do
    assert ClientAliasStep.try_match("anything", %{repo: Repo, now: @now, client_id: nil}) ==
             :no_match
  end

  test "name/0 returns :client_alias" do
    assert ClientAliasStep.name() == :client_alias
  end
end
