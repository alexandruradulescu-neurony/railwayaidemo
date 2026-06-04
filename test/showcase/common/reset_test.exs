defmodule Showcase.Common.ResetTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.Reset

  defmodule FakeSeeder do
    @behaviour Showcase.Common.DemoSeeder
    @impl true
    def name, do: "Fake"
    @impl true
    def tables, do: ["test_demo_items"]
    @impl true
    def seed do
      Ecto.Adapters.SQL.query!(Showcase.Repo, "INSERT INTO test_demo_items (label) VALUES ('seeded')")
      :ok
    end
  end

  setup do
    Ecto.Adapters.SQL.query!(
      Showcase.Repo,
      "CREATE TABLE IF NOT EXISTS test_demo_items (id SERIAL PRIMARY KEY, label TEXT NOT NULL)",
      []
    )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(Showcase.Repo, "DROP TABLE IF EXISTS test_demo_items", [])
    end)

    :ok
  end

  test "truncates and re-seeds the demo" do
    # Insert non-seed data first
    Ecto.Adapters.SQL.query!(
      Showcase.Repo,
      "INSERT INTO test_demo_items (label) VALUES ('stale')",
      []
    )

    {:ok, count_before} = item_count()
    assert count_before == 1

    assert :ok = Reset.run([FakeSeeder])

    {:ok, count_after} = item_count()
    assert count_after == 1

    {:ok, %{rows: [[label]]}} =
      Ecto.Adapters.SQL.query(Showcase.Repo, "SELECT label FROM test_demo_items", [])

    assert label == "seeded"
  end

  test "broadcasts :reset on each demo's PubSub topic" do
    # FakeSeeder.name() == "Fake" → slug "fake" → topic "demo:fake:reset"
    Phoenix.PubSub.subscribe(Showcase.PubSub, "demo:fake:reset")
    assert :ok = Reset.run([FakeSeeder])
    assert_receive {:reset, "Fake"}, 1000
  end

  defp item_count do
    case Ecto.Adapters.SQL.query(Showcase.Repo, "SELECT COUNT(*)::int FROM test_demo_items", []) do
      {:ok, %{rows: [[n]]}} -> {:ok, n}
      err -> err
    end
  end

  describe "with OrderFlow.Seed" do
    alias Showcase.OrderFlow.Schemas.{Client, Product, SyntheticMessage}
    alias Showcase.OrderFlow.Seed

    setup do
      Seed.seed()
      :ok
    end

    test "reset re-seeds OrderFlow from scratch" do
      Repo.delete_all(SyntheticMessage)
      assert Repo.aggregate(SyntheticMessage, :count) == 0

      assert :ok = Reset.run([Seed])

      assert Repo.aggregate(Client, :count) >= 3
      assert Repo.aggregate(Product, :count) >= 5
      assert Repo.aggregate(SyntheticMessage, :count) >= 4
    end
  end
end
