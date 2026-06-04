defmodule Showcase.RecruitFlow do
  @moduledoc "Public context for RecruitFlow."

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.Schemas.{Application, Position}
  alias Showcase.Repo

  def list_applications do
    Repo.all(
      from a in Application,
        order_by: [asc: a.id],
        preload: [:candidate, :position, :cvs]
    )
  end

  def applications_by_state do
    list_applications() |> Enum.group_by(& &1.state)
  end

  def find_application(id) do
    Repo.get(Application, id) |> Repo.preload([:candidate, :position, :cvs])
  end

  def list_positions, do: Repo.all(from p in Position, order_by: [asc: p.title])

  def register_mock_responses do
    Enum.each(MockPrompts.phone_scenarios(), fn s ->
      Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)
    end)

    Enum.each(MockPrompts.cv_match_scenarios(), fn s ->
      Mock.register("recruit_flow:cv_match:v1",
        scenario: s.pdf_text,
        text: ~s({"candidate_name": "#{extract_name(s.pdf_text)}", "confidence": 0.75})
      )
    end)
  end

  defp extract_name(text) do
    case Regex.run(~r/([A-Z][a-z]+ [A-Z][a-z]+)/, text) do
      [_, n] -> n
      _ -> "Unknown"
    end
  end
end
