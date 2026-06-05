defmodule Showcase.RecruitFlow.PhoneScreenPipeline do
  @moduledoc """
  Boundary that runs a phone screen for an Application.

  Flow: Claude call → parse → map outcome → Transitions.apply.

  outcome → target state:
    * "qualified"     → QUALIFIED
    * "not_qualified" → REJECTED
    * "needs_human"   → NEEDS_HUMAN
    * "callback"      → PENDING (self-loop; audit entry notes the callback)
  """

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions

  @fingerprint "recruit_flow:phone_screen:v1"
  @system_prompt """
  You are simulating a phone screen. Generate a brief transcript (3-6 exchanges)
  and score the candidate.

  Respond with JSON ONLY in this shape:
    {
      "transcript": "<3-6 exchange dialog>",
      "outcome": "qualified" | "not_qualified" | "callback" | "needs_human",
      "reasoning": "<one sentence>",
      "score": 0.0 to 1.0
    }
  """

  @outcome_to_state %{
    "qualified" => "QUALIFIED",
    "not_qualified" => "REJECTED",
    "needs_human" => "NEEDS_HUMAN",
    "callback" => "PENDING"
  }

  @spec run(Application.t(), %{now: DateTime.t(), scenario: String.t()}) ::
          {:ok, Application.t()} | {:error, term()}
  def run(%Application{} = app, %{now: _now, scenario: scenario}) do
    req = %Request{
      model: Config.default_model(),
      messages: [%{role: "user", content: "Run a phone screen."}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, parsed, _completeness} <- ResilientJSONParser.parse(response.text),
         {:ok, target} <- target_state(parsed["outcome"]),
         {:ok, updated} <-
           Transitions.apply(app.id, target,
             actor: "system",
             reason: "ai_screen:#{parsed["outcome"]}",
             transcript: parsed["transcript"],
             eval: parsed
           ) do
      {:ok, updated}
    end
  end

  defp target_state(outcome) do
    case Map.get(@outcome_to_state, outcome) do
      nil -> {:error, {:unknown_outcome, outcome}}
      state -> {:ok, state}
    end
  end
end
