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

  describe "seed/0" do
    test "creates 1 planogram + 3 tasks with distinct scenarios" do
      :ok = Seed.seed()

      planograms = Repo.all(Planogram)
      assert length(planograms) >= 1

      tasks = Repo.all(from t in VerificationTask, order_by: t.id)
      assert length(tasks) == 3
      scenarios = Enum.map(tasks, & &1.scenario) |> Enum.sort()
      assert scenarios == ["compliant", "major_issues", "minor_issues"]

      # Each task has a unique mobile_token
      tokens = Enum.map(tasks, & &1.mobile_token)
      assert length(Enum.uniq(tokens)) == 3

      # One task has due_date in the past (for overdue demo)
      today = Date.utc_today()
      assert Enum.any?(tasks, &(Date.compare(&1.due_date, today) == :lt))
    end

    test "is idempotent" do
      :ok = Seed.seed()
      first_count = Repo.aggregate(VerificationTask, :count)
      :ok = Seed.seed()
      assert Repo.aggregate(VerificationTask, :count) == first_count
    end
  end
end
