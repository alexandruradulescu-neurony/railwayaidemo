defmodule Showcase.RecruitFlow.CascadeTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.Cascade.{
    ExactEmailStep,
    ExactPhoneStep,
    FuzzyNameStep,
    PdfContentStep,
    SubjectLineStep
  }
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
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

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now()}

  describe "ExactEmailStep" do
    test "matches Application by candidate email", %{app: app} do
      input = %{email: "alice@example.com", phone: nil, subject_line: nil, pdf_text: ""}
      assert {:match, application_id, 1.0} = ExactEmailStep.try_match(input, ctx())
      assert application_id == app.id
    end

    test "no_match on unknown email" do
      input = %{email: "ghost@nowhere.com", phone: nil, subject_line: nil, pdf_text: ""}
      assert ExactEmailStep.try_match(input, ctx()) == :no_match
    end

    test "name/0 returns :exact_email" do
      assert ExactEmailStep.name() == :exact_email
    end
  end

  describe "ExactPhoneStep" do
    test "matches by phone", %{app: app} do
      input = %{email: nil, phone: "+1-555-0101", subject_line: nil, pdf_text: ""}
      assert {:match, application_id, 1.0} = ExactPhoneStep.try_match(input, ctx())
      assert application_id == app.id
    end
  end

  describe "SubjectLineStep" do
    test "matches Application #C-<id> pattern", %{app: app} do
      input = %{email: nil, phone: nil, subject_line: "RE: Application #C-#{app.id}", pdf_text: ""}
      assert {:match, application_id, 1.0} = SubjectLineStep.try_match(input, ctx())
      assert application_id == app.id
    end

    test "no_match when subject doesn't match pattern" do
      input = %{email: nil, phone: nil, subject_line: "Just a CV", pdf_text: ""}
      assert SubjectLineStep.try_match(input, ctx()) == :no_match
    end
  end

  describe "FuzzyNameStep" do
    test "matches by similar name in pdf_text", %{app: app} do
      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "Alice Anderson — Senior Engineer..."}
      assert {:match, application_id, score} = FuzzyNameStep.try_match(input, ctx())
      assert application_id == app.id
      assert score >= 0.6
    end

    test "no_match for unrelated name" do
      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "Zebra Zulu — completely different"}
      assert FuzzyNameStep.try_match(input, ctx()) == :no_match
    end
  end

  describe "PdfContentStep" do
    test "matches via Claude content analysis", %{app: app, candidate: candidate} do
      Mock.register("recruit_flow:cv_match:v1",
        scenario: "uncommon_phrasing",
        text: ~s({"candidate_name": "#{candidate.name}", "confidence": 0.75})
      )

      input = %{
        email: nil,
        phone: nil,
        subject_line: nil,
        pdf_text: "uncommon_phrasing"
      }

      assert {:match, application_id, score} = PdfContentStep.try_match(input, ctx())
      assert application_id == app.id
      assert score == 0.75
    end

    test "no_match when Claude returns unknown name" do
      Mock.register("recruit_flow:cv_match:v1",
        scenario: "ghost",
        text: ~s({"candidate_name": "Nonexistent Person", "confidence": 0.9})
      )

      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "ghost"}
      assert PdfContentStep.try_match(input, ctx()) == :no_match
    end
  end
end
