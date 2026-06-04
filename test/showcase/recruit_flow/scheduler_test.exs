defmodule Showcase.RecruitFlow.SchedulerTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Scheduler
  alias Showcase.Repo

  setup do
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, %{position: position}}
  end

  defp insert_app(position, state, ts) do
    {:ok, c} = Repo.insert(%Candidate{name: "C-#{System.unique_integer([:positive])}"})

    {:ok, a} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: c.id,
        position_id: position.id,
        state: state,
        state_changed_at: ts
      })
      |> Repo.insert()

    a
  end

  test "auto_close_stale_qualified only touches QUALIFIED older than 7 days", %{position: position} do
    now = DateTime.utc_now()
    fresh = insert_app(position, "QUALIFIED", DateTime.add(now, -3, :day))
    stale = insert_app(position, "QUALIFIED", DateTime.add(now, -10, :day))
    rejected = insert_app(position, "REJECTED", DateTime.add(now, -10, :day))

    count = Scheduler.auto_close_stale_qualified(%{now: now})
    assert count == 1

    assert Repo.get!(Application, fresh.id).state == "QUALIFIED"
    assert Repo.get!(Application, stale.id).state == "REJECTED"
    assert Repo.get!(Application, rejected.id).state == "REJECTED"
  end

  test "tick_all returns a summary map", %{position: position} do
    insert_app(position, "QUALIFIED", DateTime.add(DateTime.utc_now(), -10, :day))

    summary = Scheduler.tick_all(%{now: DateTime.utc_now()})
    assert is_map(summary)
    assert Map.has_key?(summary, :auto_close_stale_qualified)
  end
end
