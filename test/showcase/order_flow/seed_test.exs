defmodule Showcase.OrderFlow.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Seed
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  test "name/0 returns 'OrderFlow'" do
    assert Seed.name() == "OrderFlow"
  end

  test "description/0 returns a one-line value-framing copy" do
    description = Seed.description()
    assert is_binary(description)
    # Sanity: short enough for a tile, contains a meaningful phrase
    assert String.length(description) > 20
    assert String.length(description) < 200
  end

  test "tables/0 returns of_* tables in child-before-parent order" do
    tables = Seed.tables()
    assert "of_order_lines" in tables
    assert "of_orders" in tables
    assert "of_product_aliases" in tables
    assert "of_synthetic_messages" in tables
    assert "of_products" in tables
    assert "of_clients" in tables
    # children before parents
    assert Enum.find_index(tables, &(&1 == "of_order_lines")) <
             Enum.find_index(tables, &(&1 == "of_orders"))
  end

  test "oban_queue/0 returns :order_flow" do
    assert Seed.oban_queue() == :order_flow
  end

  test "seed/0 populates clients, products, aliases, messages" do
    assert :ok = Seed.seed()

    assert Repo.aggregate(Client, :count) >= 3
    assert Repo.aggregate(Product, :count) >= 5
    assert Repo.aggregate(ProductAlias, :count) >= 1
    assert Repo.aggregate(SyntheticMessage, :count) >= 3
  end

  test "seed/0 is idempotent — running twice produces the same state" do
    assert :ok = Seed.seed()
    {clients_a, products_a, aliases_a, messages_a} = counts()

    assert :ok = Seed.seed()
    {clients_b, products_b, aliases_b, messages_b} = counts()

    assert clients_a == clients_b
    assert products_a == products_b
    assert aliases_a == aliases_b
    assert messages_a == messages_b
  end

  defp counts do
    {
      Repo.aggregate(Client, :count),
      Repo.aggregate(Product, :count),
      Repo.aggregate(ProductAlias, :count),
      Repo.aggregate(SyntheticMessage, :count)
    }
  end
end
