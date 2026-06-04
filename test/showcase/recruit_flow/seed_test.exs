defmodule Showcase.RecruitFlow.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Seed
  alias Showcase.Repo

  test "name + description + oban_queue" do
    assert Seed.name() == "RecruitFlow"
    assert is_binary(Seed.description())
    assert Seed.oban_queue() == :recruit_flow
  end

  test "tables/0 returns rf_* tables children-before-parents" do
    tables = Seed.tables()
    assert "rf_cvs" in tables
    assert "rf_applications" in tables
    assert "rf_candidates" in tables
    assert "rf_positions" in tables
  end

  test "seed/0 populates positions, candidates, applications" do
    assert :ok = Seed.seed()
    assert Repo.aggregate(Position, :count) >= 1
    assert Repo.aggregate(Candidate, :count) >= 4
    assert Repo.aggregate(Application, :count) >= 4
  end

  test "seed/0 is idempotent" do
    assert :ok = Seed.seed()
    a = {Repo.aggregate(Position, :count), Repo.aggregate(Candidate, :count), Repo.aggregate(Application, :count)}
    assert :ok = Seed.seed()
    b = {Repo.aggregate(Position, :count), Repo.aggregate(Candidate, :count), Repo.aggregate(Application, :count)}
    assert a == b
  end
end
