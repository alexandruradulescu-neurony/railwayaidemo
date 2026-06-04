defmodule Showcase.OrderFlow.Cascade.GlobalAliasStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.GlobalAliasStep
  alias Showcase.OrderFlow.Schemas.{Product, ProductAlias}
  alias Showcase.Repo

  @now ~U[2026-06-04 12:00:00.000000Z]

  setup do
    {:ok, gasket} =
      %Product{}
      |> Product.changeset(%{sku: "GSK-4MM", name: "4mm Gasket", normalized_name: "4mm gasket"})
      |> Repo.insert()

    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: nil,
        confidence: 0.78,
        last_used_at: one_month_ago,
        source: "promotion"
      })
      |> Repo.insert()

    {:ok, %{gasket: gasket}}
  end

  defp ctx, do: %{repo: Repo, now: @now, client_id: nil}

  test "returns match when fresh global alias exists", %{gasket: gasket} do
    {:match, found, score} = GlobalAliasStep.try_match("The 4mm Gaskets", ctx())
    assert found.id == gasket.id
    assert score == 0.78
  end

  test "matches even when client_id is supplied in context", %{gasket: gasket} do
    # Global aliases should be tried regardless of client_id in context
    ctx_with_client = %{ctx() | client_id: 42}
    {:match, found, _score} = GlobalAliasStep.try_match("the 4mm gaskets", ctx_with_client)
    assert found.id == gasket.id
  end

  test "no_match when nothing in global pool" do
    Repo.delete_all(ProductAlias)
    assert GlobalAliasStep.try_match("anything", ctx()) == :no_match
  end

  test "name/0 returns :global_alias" do
    assert GlobalAliasStep.name() == :global_alias
  end
end
