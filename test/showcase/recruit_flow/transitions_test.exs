defmodule Showcase.RecruitFlow.TransitionsTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  setup do
    {:ok, candidate} = Repo.insert(%Candidate{name: "Alice Test"})
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "PENDING",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app}}
  end

  test "apply/3 succeeds for an allowed transition", %{app: app} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")

    {:ok, updated} = Transitions.apply(app.id, "QUALIFIED", actor: "system", reason: "ai_qualified")
    assert updated.state == "QUALIFIED"
    assert_received {:recruit_flow, :transitioned, %{application_id: _, from: "PENDING", to: "QUALIFIED"}}
  end

  test "apply/3 supports the PENDING self-loop for callback outcomes", %{app: app} do
    {:ok, updated} = Transitions.apply(app.id, "PENDING", actor: "system", reason: "callback")
    assert updated.state == "PENDING"
  end

  test "apply/3 returns error for disallowed transition", %{app: app} do
    assert {:error, :invalid_transition} =
             Transitions.apply(app.id, "HIRED", actor: "system", reason: "skip")
  end

  test "apply/3 writes an AuditLog entry on success", %{app: app} do
    {:ok, _} = Transitions.apply(app.id, "QUALIFIED", actor: "system", reason: "ai_qualified")

    {:ok, audits} = Showcase.Common.AuditLog.for_entity("recruit_flow", "application", to_string(app.id))
    assert Enum.any?(audits, &(&1.event == "state_change"))
  end

  test "apply/3 updates eval/transcript when provided", %{app: app} do
    {:ok, app2} =
      Transitions.apply(app.id, "QUALIFIED",
        actor: "system",
        reason: "ai_qualified",
        transcript: "Hello!",
        eval: %{"outcome" => "qualified", "score" => 0.9, "reasoning" => "Good fit"}
      )

    assert app2.transcript == "Hello!"
    assert app2.eval["outcome"] == "qualified"
  end
end
