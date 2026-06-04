defmodule Showcase.RecruitFlow.CvMatcherTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.CvMatcher
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Cv, Position}
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, candidate} =
      %Candidate{}
      |> Candidate.changeset(%{
        name: "Alice Anderson",
        email: "alice@example.com",
        phone: "+1-555-0101"
      })
      |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "QUALIFIED",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app, candidate: candidate}}
  end

  test "process_cv with matching email → Application transitions to HIRED", %{app: app} do
    payload = %{
      email: "alice@example.com",
      phone: nil,
      subject_line: nil,
      pdf_text: "Alice Anderson resume body"
    }

    {:ok, cv, outcome} = CvMatcher.process_cv(payload, %{now: DateTime.utc_now()})

    assert outcome.matched
    assert outcome.step == :exact_email
    assert cv.application_id == app.id
    assert cv.match_step == "exact_email"

    updated_app = Repo.get!(Application, app.id)
    assert updated_app.state == "HIRED"
  end

  test "process_cv with no match → returns :no_match" do
    payload = %{
      email: "ghost@nowhere.com",
      phone: nil,
      subject_line: nil,
      pdf_text: "Random PDF nothing matches"
    }

    {:no_match, outcome} = CvMatcher.process_cv(payload, %{now: DateTime.utc_now()})
    refute outcome.matched
  end
end
