defmodule Showcase.RestaurantCompliance.MockPrompts do
  @moduledoc """
  Canned scenarios registered on `AnthropicClient.Mock` for the Restaurant
  Compliance vision pipeline. Used in tests / when ANTHROPIC_API_KEY is
  unset. Three scenarios: `compliant`, `mixed`, `non_compliant`.
  """

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.Common.AnthropicClient.Types.{Response, Usage}
  alias Showcase.RestaurantCompliance.Impl.VisionRequest

  @spec register_all() :: :ok
  def register_all do
    for {scenario, text, usage} <- scenarios() do
      Mock.register(VisionRequest.fingerprint(),
        scenario: scenario,
        text: text,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cost_estimate_cents: usage.cost_estimate_cents
      )
    end

    :ok
  end

  @doc """
  Look up a scripted response for a seeded scenario tag. Returns a
  fully-formed `%Response{}` so the VisionPipeline can bypass the real
  `AnthropicClient.call/1` entirely — predictable demo, no API tokens
  burnt, no flake on real Claude variance.

  Returns `:not_found` for any scenario not in the seeded set.
  """
  @spec scripted_response_for(String.t() | nil) :: {:ok, Response.t()} | :not_found
  def scripted_response_for(scenario) when is_binary(scenario) do
    case Enum.find(scenarios(), fn {s, _, _} -> s == scenario end) do
      {_, text, usage} ->
        {:ok, %Response{text: text, usage: struct(Usage, usage)}}

      nil ->
        :not_found
    end
  end

  def scripted_response_for(_), do: :not_found

  defp scenarios do
    [
      {"compliant", compliant_json(),
       %{input_tokens: 3800, output_tokens: 480, cost_estimate_cents: 1.78}},
      {"mixed", mixed_json(),
       %{input_tokens: 3800, output_tokens: 720, cost_estimate_cents: 2.06}},
      {"non_compliant", non_compliant_json(),
       %{input_tokens: 3800, output_tokens: 950, cost_estimate_cents: 2.34}}
    ]
  end

  defp compliant_json do
    Jason.encode!(%{
      compliance_score: 96,
      overall_summary:
        "Restaurant matches the mise-en-place standard. Flatware, glassware, and central elements are all aligned to the reference. Floor and table tops are clean.",
      rule_evaluations: [
        %{rule: "Bottle facings", status: "pass", severity: "low",
          evidence: "Bottles on the lazy Susan face outward; labels visible.",
          photo_indices: [1, 2]},
        %{rule: "Flatware alignment", status: "pass", severity: "low",
          evidence: "Knives and forks aligned precisely with plates.",
          photo_indices: [2, 3]},
        %{rule: "Glassware arrangement", status: "pass", severity: "low",
          evidence: "Water, red, and white wine glasses arranged in consistent pattern.",
          photo_indices: [3]},
        %{rule: "Floor cleanliness", status: "pass", severity: "low",
          evidence: "Floor free of debris.", photo_indices: [4]}
      ],
      photo_violations: [],
      remediation_steps: ["No action required — restaurant is in full compliance."]
    })
  end

  defp mixed_json do
    Jason.encode!(%{
      compliance_score: 72,
      overall_summary:
        "Mostly compliant with two notable drifts: flatware alignment is inconsistent on Photo 2, and a glass is missing from one setting in Photo 3. Central elements and floor are fine.",
      rule_evaluations: [
        %{rule: "Bottle facings", status: "pass", severity: "low",
          evidence: "Bottles on the lazy Susan face outward correctly.",
          photo_indices: [1]},
        %{rule: "Card placement", status: "pass", severity: "low",
          evidence: "Red text card centered.", photo_indices: [1]},
        %{rule: "Flatware alignment", status: "partial", severity: "medium",
          evidence: "Knife on the right setting of Photo 2 is angled — not parallel to plate edge.",
          photo_indices: [2]},
        %{rule: "Napkins folded on plates", status: "pass", severity: "low",
          evidence: "Dark grey linen napkins, neatly folded.", photo_indices: [2, 3]},
        %{rule: "Glassware arrangement", status: "fail", severity: "medium",
          evidence: "Photo 3 left setting is missing the white wine glass.",
          photo_indices: [3]},
        %{rule: "Floor cleanliness", status: "pass", severity: "low",
          evidence: "Floor clean, no fallen napkins visible.",
          photo_indices: [4]}
      ],
      photo_violations: [
        %{photo_index: 2,
          issues: [%{description: "Right knife not parallel to plate.", severity: "medium"}]},
        %{photo_index: 3,
          issues: [%{description: "White wine glass missing from left setting.", severity: "medium"}]}
      ],
      remediation_steps: [
        "Re-align right knife on Photo 2's right setting.",
        "Replace missing white wine glass on Photo 3's left setting before service."
      ]
    })
  end

  defp non_compliant_json do
    Jason.encode!(%{
      compliance_score: 38,
      overall_summary:
        "Major non-conformance. Flatware misaligned across multiple settings, two glasses missing, a used dish left on the table, and a fallen napkin on the floor. Recommend full reset before service.",
      rule_evaluations: [
        %{rule: "Bottle facings", status: "fail", severity: "medium",
          evidence: "Bottle labels turned away from diners on the lazy Susan.",
          photo_indices: [1]},
        %{rule: "Grinders position", status: "partial", severity: "low",
          evidence: "Grinders present but not in their standard position.",
          photo_indices: [1]},
        %{rule: "Flatware alignment", status: "fail", severity: "high",
          evidence: "Flatware misaligned on at least three settings in Photos 2 and 3.",
          photo_indices: [2, 3]},
        %{rule: "Napkins folded on plates", status: "fail", severity: "medium",
          evidence: "Two settings have napkins loose, not folded on plates.",
          photo_indices: [2, 3]},
        %{rule: "Glassware arrangement", status: "fail", severity: "high",
          evidence: "Two settings missing wine glasses entirely.",
          photo_indices: [3]},
        %{rule: "Tables cleared between services", status: "fail", severity: "high",
          evidence: "Used dessert plate left on a table in Photo 2.",
          photo_indices: [2]},
        %{rule: "Floor cleanliness", status: "fail", severity: "medium",
          evidence: "Fallen napkin visible on floor in Photo 4.",
          photo_indices: [4]}
      ],
      photo_violations: [
        %{photo_index: 1,
          issues: [%{description: "Bottle labels facing inward.", severity: "medium"}]},
        %{photo_index: 2,
          issues: [
            %{description: "Three flatware items misaligned.", severity: "high"},
            %{description: "Used dessert plate left on table.", severity: "high"}
          ]},
        %{photo_index: 3,
          issues: [
            %{description: "Two wine glasses missing.", severity: "high"},
            %{description: "Napkins not folded.", severity: "medium"}
          ]},
        %{photo_index: 4,
          issues: [%{description: "Napkin on floor.", severity: "medium"}]}
      ],
      remediation_steps: [
        "Turn all bottle labels outward on the lazy Susan.",
        "Re-align flatware on every setting — knives right, forks left, parallel to plates.",
        "Replace the two missing wine glasses immediately.",
        "Clear the used dessert plate from the table in Photo 2.",
        "Pick up the fallen napkin from the floor."
      ]
    })
  end
end
