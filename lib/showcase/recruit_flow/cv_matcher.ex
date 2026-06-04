defmodule Showcase.RecruitFlow.CvMatcher do
  @moduledoc """
  Boundary that runs the 5-priority CV cascade and transitions the matched
  Application from QUALIFIED → HIRED.
  """

  alias Showcase.Common.CascadeMatcher

  alias Showcase.RecruitFlow.Cascade.{
    ExactEmailStep,
    ExactPhoneStep,
    FuzzyNameStep,
    PdfContentStep,
    SubjectLineStep
  }

  alias Showcase.RecruitFlow.Schemas.Cv
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @cascade_steps [
    ExactEmailStep,
    ExactPhoneStep,
    SubjectLineStep,
    FuzzyNameStep,
    PdfContentStep
  ]

  def process_cv(payload, %{now: now}) do
    context = %{repo: Repo, now: now}
    outcome = CascadeMatcher.run(@cascade_steps, payload, context)

    if outcome.matched do
      {:ok, cv} =
        %Cv{}
        |> Cv.changeset(%{
          application_id: outcome.value,
          candidate_email: payload.email,
          candidate_phone: payload.phone,
          subject_line: payload.subject_line,
          pdf_text: payload.pdf_text,
          received_at: now,
          match_step: Atom.to_string(outcome.step),
          match_confidence: outcome.confidence
        })
        |> Repo.insert()

      {:ok, _} =
        Transitions.apply(outcome.value, "HIRED",
          actor: "system",
          reason: "cv_matched:#{outcome.step}"
        )

      {:ok, cv, outcome}
    else
      {:no_match, outcome}
    end
  end
end
