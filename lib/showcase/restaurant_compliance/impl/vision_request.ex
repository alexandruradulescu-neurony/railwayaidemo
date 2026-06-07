defmodule Showcase.RestaurantCompliance.Impl.VisionRequest do
  @moduledoc """
  Pure builder for the Restaurant Compliance vision `AnthropicClient.Request`.

  Inputs:
    * the rules document (text)
    * 0..N reference standard images (illustrated mise-en-place guides)
    * 1..N inspection photos (uploaded by the inspector)

  Output a single user message with content blocks in this exact order:

    1. each reference image (base64 image block)
    2. each inspection photo (base64 image block)
    3. one text block describing the task, photo numbering, and the rules

  Photos are labeled in the text block as "Reference 1, Reference 2, ...,
  Inspection photo 1, Inspection photo 2, ..." so Claude can reference them
  by index in the structured response.

  Does NOT read the filesystem — boundary code reads the photo bytes.
  """

  alias Showcase.Common.AnthropicClient.Types.Request

  @fingerprint "restaurant_compliance_vision_v1"

  @system_prompt """
  You are a restaurant operations inspector. Your task is to evaluate
  whether the photos uploaded by a field inspector show a restaurant
  setting that conforms to a mise-en-place compliance ruleset.

  The user message contains, in order:
    1. Zero or more REFERENCE STANDARD images — illustrated guides showing
       the ideal mise-en-place layout.
    2. One or more INSPECTION PHOTOS — actual photographs taken by the
       inspector at the restaurant.
    3. A text block containing the rules document and explicit numbering
       for both reference and inspection photos.

  Compare the inspection photos against the rules text AND the reference
  images. Identify every rule-level pass / fail / partial / not-applicable
  judgement, plus per-photo violations.

  Return a JSON object with this exact shape:

  {
    "compliance_score": <0-100 integer — weighted by severity>,
    "overall_summary": "<one short paragraph summarizing the inspection>",
    "rule_evaluations": [
      {
        "rule": "<short rule name, e.g. 'Flatware alignment'>",
        "status": "pass" | "partial" | "fail" | "not_applicable",
        "severity": "low" | "medium" | "high",
        "evidence": "<text — what you observed in the photos>",
        "photo_indices": [<1-based inspection-photo indices that show this>]
      }
    ],
    "photo_violations": [
      {
        "photo_index": <1-based inspection photo index>,
        "issues": [
          {"description": "<text>", "severity": "low" | "medium" | "high"}
        ]
      }
    ],
    "remediation_steps": ["<actionable, restaurant-staff-readable item>"]
  }

  Notes on status meaning:
    * "pass" — the rule is clearly satisfied in the inspection photos.
    * "partial" — mostly satisfied but with visible drift or one exception.
    * "fail" — the rule is clearly violated.
    * "not_applicable" — the rule's subject does not appear in any
      inspection photo (e.g. floor cleanliness with no floor shots).

  Notes on severity:
    * "high" — affects food safety, customer experience, or revenue.
    * "medium" — visible drift; correctable on the next service.
    * "low" — minor or cosmetic.

  Output ONLY the JSON. No prose. No code fences.
  """

  @doc "The active system prompt text. Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @doc """
  Build the vision Request.

  ## Args
    * `ruleset` — map with `:name`, `:rules_text`
    * `inspection_photo_bytes` — list of binaries (one per inspection photo)
    * `reference_bytes_list` — list of binaries (one per reference image; may be empty)
    * `opts` — keyword:
      * `:scenario` — string for Mock keying. Default `"mixed"`.
      * `:max_tokens` — default 4096.
  """
  @spec build(map(), list(binary()), list(binary()), keyword()) :: Request.t()
  def build(ruleset, inspection_photo_bytes, reference_bytes_list, opts \\ [])
      when is_list(inspection_photo_bytes) and is_list(reference_bytes_list) do
    scenario = Keyword.get(opts, :scenario, "mixed")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    reference_blocks = Enum.map(reference_bytes_list, &image_block/1)
    inspection_blocks = Enum.map(inspection_photo_bytes, &image_block/1)
    text = task_text(ruleset, length(reference_bytes_list), length(inspection_photo_bytes))

    content_blocks = reference_blocks ++ inspection_blocks ++ [text_block(text)]

    %Request{
      model: "claude-sonnet-4-5",
      system: @system_prompt,
      max_tokens: max_tokens,
      messages: [%{role: "user", content: content_blocks}],
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }
  end

  defp image_block(bytes) do
    %{
      "type" => "image",
      "source" => %{
        "type" => "base64",
        "media_type" => media_type(bytes),
        "data" => Base.encode64(bytes)
      }
    }
  end

  defp text_block(text), do: %{"type" => "text", "text" => text}

  defp task_text(%{name: name, rules_text: rules_text}, ref_count, photo_count) do
    """
    Ruleset: "#{name}"

    Images attached above, in order:
    #{photo_legend(ref_count, photo_count)}

    Rules document:

    #{rules_text}

    Evaluate each rule from the document against the INSPECTION photos
    (using the REFERENCE images as the visual standard when present).
    Return the JSON shape defined in the system prompt.
    """
  end

  defp photo_legend(0, photo_count) do
    "  * #{photo_count} inspection #{if photo_count == 1, do: "photo", else: "photos"} (numbered 1..#{photo_count})"
  end

  defp photo_legend(ref_count, photo_count) do
    "  * #{ref_count} reference #{if ref_count == 1, do: "image", else: "images"} (numbered 1..#{ref_count})\n" <>
      "  * #{photo_count} inspection #{if photo_count == 1, do: "photo", else: "photos"} (numbered 1..#{photo_count})"
  end

  @spec media_type(binary()) :: String.t()
  def media_type(<<137, 80, 78, 71, _::binary>>), do: "image/png"
  def media_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def media_type(<<"GIF87a", _::binary>>), do: "image/gif"
  def media_type(<<"GIF89a", _::binary>>), do: "image/gif"
  def media_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  def media_type(_), do: "image/jpeg"

  @doc false
  def fingerprint, do: @fingerprint
end
