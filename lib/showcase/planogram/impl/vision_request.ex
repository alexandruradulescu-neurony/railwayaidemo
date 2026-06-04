defmodule Showcase.Planogram.Impl.VisionRequest do
  @moduledoc """
  Pure builder for the planogram vision `AnthropicClient.Request`.

  Takes a planogram (with expected_rows) + photo bytes + opts, returns a
  Request with the vision content blocks, system prompt, and metadata
  keyed by `{fingerprint, scenario}` for Mock matching.

  Does NOT read the filesystem — boundary code reads the photo and passes
  bytes in.
  """

  alias Showcase.Common.AnthropicClient.Types.Request

  @fingerprint "planogram_vision_v1"

  @system_prompt """
  You are a retail merchandising auditor. Given a reference planogram
  (expected rows + products) and a photo of an actual shelf, return a
  STRICT JSON object with the following shape:

  {
    "compliance_score": <0-100 integer>,
    "executive_summary": "<one-paragraph readable summary>",
    "rows": [
      {
        "name": "<row name>",
        "position": <int>,
        "status": "compliant" | "partial" | "non_compliant",
        "found_products": [{"sku": "<sku>", "name": "<name>", "qty": <int>}],
        "issues": ["<short issue strings>"]
      }
    ],
    "issues": [
      {
        "type": "missing_product" | "wrong_position" | "wrong_qty" | "unauthorized_item" | "photo_quality",
        "severity": "low" | "medium" | "high",
        "description": "<text>",
        "business_impact": "<text>"
      }
    ],
    "unauthorized_items": [{"name": "<name>", "row": <int>}],
    "suggestions": ["<actionable suggestion>"],
    "photo_quality": {"score": <0-100>, "notes": "<text>"},
    "extracted_products": [{"sku": "<sku>", "name": "<name>", "qty": <int>}]
  }

  Output ONLY the JSON. No prose. No code fences.
  """

  @spec build(map(), binary(), keyword()) :: Request.t()
  def build(planogram, photo_bytes, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, "compliant")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    %Request{
      model: "claude-sonnet-4-5",
      system: @system_prompt,
      max_tokens: max_tokens,
      messages: [
        %{
          "role" => "user",
          "content" => [
            %{
              "type" => "image",
              "source" => %{
                "type" => "base64",
                "media_type" => media_type(photo_bytes),
                "data" => Base.encode64(photo_bytes)
              }
            },
            %{
              "type" => "text",
              "text" => user_text(planogram)
            }
          ]
        }
      ],
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }
  end

  @spec media_type(binary()) :: String.t()
  def media_type(<<137, 80, 78, 71, _::binary>>), do: "image/png"
  def media_type(_), do: "image/jpeg"

  @doc false
  def fingerprint, do: @fingerprint

  defp user_text(%{name: name, expected_rows: rows}) do
    """
    Reference planogram: "#{name}"

    Expected rows:
    #{Jason.encode!(rows, pretty: true)}

    The image attached above is a photo of the actual shelf. Audit
    compliance and return the JSON shape described in the system prompt.
    """
  end
end
