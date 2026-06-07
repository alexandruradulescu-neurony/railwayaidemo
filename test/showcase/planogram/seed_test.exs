defmodule Showcase.Planogram.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram.{Planogram, VerificationTask, Seed}
  alias Showcase.Repo
  import Ecto.Query

  describe "DemoSeeder contract" do
    test "name/0 returns 'Planogram Manager'" do
      assert Seed.name() == "Planogram Manager"
    end

    test "description/0 returns a non-empty string" do
      assert is_binary(Seed.description())
      assert String.length(Seed.description()) > 20
    end

    test "tables/0 lists the pg_ tables in dependency-aware order" do
      assert Seed.tables() == ["pg_verification_tasks", "pg_planograms"]
    end

    test "oban_queue/0 returns :planogram" do
      assert Seed.oban_queue() == :planogram
    end
  end

  describe "seed/0 (demo baseline)" do
    test "creates 2 reference planograms (pharmacy + juices) + 5 tasks" do
      :ok = Seed.seed()
      assert Repo.aggregate(Planogram, :count) == 2
      assert Repo.aggregate(VerificationTask, :count) == 5

      names = Repo.all(Planogram) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Natural juices aisle", "Pharmacy OTC end-cap"]
    end

    test "is idempotent" do
      :ok = Seed.seed()
      :ok = Seed.seed()
      assert Repo.aggregate(Planogram, :count) == 2
      assert Repo.aggregate(VerificationTask, :count) == 5
    end
  end

end
