defmodule Showcase.RecruitFlow.Seed do
  @moduledoc "Seeds RecruitFlow with positions, candidates, applications."

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  @impl true
  def name, do: "RecruitFlow"

  @impl true
  def description do
    "Phone-screen, score, and chase candidates through a 5-state funnel. Recruiters intervene only on the ambiguous middle."
  end

  @impl true
  def oban_queue, do: :recruit_flow

  @impl true
  def tables do
    ["rf_cvs", "rf_applications", "rf_candidates", "rf_positions"]
  end

  @impl true
  def seed do
    Repo.transaction(fn ->
      position = seed_position()
      seed_applications(position)
    end)
    |> case do
      {:ok, _} ->
        seed_system_prompts()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "recruit_flow",
      "phone_screen",
      Showcase.RecruitFlow.PhoneScreenPipeline.system_prompt(),
      note: "Conducts a structured phone screen and returns transcript + eval."
    )

    Showcase.Common.SystemPromptSeeder.upsert(
      "recruit_flow",
      "cv_match",
      Showcase.RecruitFlow.Cascade.PdfContentStep.system_prompt(),
      note: "Matches a CV PDF to known candidates by free-text content."
    )
  end

  defp seed_position do
    case Repo.get_by(Position, title: "Software Engineer") do
      nil ->
        {:ok, p} =
          %Position{}
          |> Position.changeset(%{
            title: "Software Engineer",
            department: "Engineering",
            prompt_section: "se_v1",
            default_prompt_body: "You are screening for a Software Engineer role at Neurony."
          })
          |> Repo.insert()
        p

      existing -> existing
    end
  end

  defp seed_applications(position) do
    Enum.each(MockPrompts.phone_scenarios(), fn s ->
      candidate =
        case Repo.get_by(Candidate, name: s.candidate.name) do
          nil ->
            {:ok, c} = %Candidate{} |> Candidate.changeset(s.candidate) |> Repo.insert()
            c
          existing -> existing
        end

      case Repo.get_by(Application, candidate_id: candidate.id, position_id: position.id) do
        nil ->
          %Application{}
          |> Application.changeset(%{
            candidate_id: candidate.id,
            position_id: position.id,
            state: "PENDING",
            state_changed_at: DateTime.utc_now()
          })
          |> Repo.insert!()

        _ -> :noop
      end
    end)
  end
end
