defmodule Showcase.RecruitFlow.PhoneScreenPipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.PhoneScreenPipeline
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, %{position: position}}
  end

  defp insert_app(position, candidate_attrs) do
    {:ok, c} = %Candidate{} |> Candidate.changeset(candidate_attrs) |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: c.id,
        position_id: position.id,
        state: "PENDING",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    app
  end

  defp ctx_with(scenario), do: %{now: DateTime.utc_now(), scenario: scenario}

  test "qualified outcome → QUALIFIED", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "alice_qualified"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "QUALIFIED"
    assert updated.eval["outcome"] == "qualified"
    assert is_binary(updated.transcript)
  end

  test "not_qualified outcome → REJECTED", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "bob_not_qualified"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "REJECTED"
  end

  test "needs_human outcome → NEEDS_HUMAN", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "dan_needs_human"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "NEEDS_HUMAN"
  end

  test "callback outcome stays in PENDING (with audit entry)", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "carol_callback"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "PENDING"

    {:ok, audits} = Showcase.Common.AuditLog.for_entity("recruit_flow", "application", to_string(app.id))
    assert Enum.any?(audits, fn a -> a.event == "state_change" and a.payload["reason"] =~ "callback" end)
  end
end
