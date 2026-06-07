defmodule Showcase.Planogram.Impl.VisionRequest do
  @moduledoc """
  Pure builder for the planogram vision `AnthropicClient.Request`.

  Two modes:

    * **Two-image comparison** (preferred when both images are available): the
      message carries one image block for the reference planogram, then a
      second for the actual shelf photo, then a text block describing the
      task. Claude is asked to compare them visually.
    * **Single-image audit** (fallback when only the shelf photo is at hand):
      reference is described in `expected_rows` JSON. Same output shape.

  Does NOT read the filesystem — boundary code reads the photos and passes
  bytes in.
  """

  alias Showcase.Common.AnthropicClient.Types.Request

  @fingerprint "planogram_vision_v1"

  @system_prompt """
  You are a retail merchandising auditor. Your task is to compare an actual
  shelf against a reference planogram and produce a STRICT JSON compliance
  report.

  The user message contains either:
    * Two images — image 1 is the REFERENCE planogram (what the shelf
      SHOULD look like), image 2 is the ACTUAL shelf photo.
    * One image — the actual shelf photo. In this case a text description
      of the expected layout will accompany it.

  When in two-image mode: visually compare the two and call out what
  differs. When in one-image mode: audit the shelf against the text
  description.

  Return a JSON object with this shape:

  {
    "compliance_score": <0-100 integer>,
    "executive_summary": "<one-paragraph readable summary>",
    "issues": [
      {
        "type": "missing_product" | "wrong_placement" | "wrong_qty" | "out_of_stock" | "unauthorized_item" | "photo_quality" | "mismatch",
        "severity": "low" | "medium" | "high",
        "description": "<text>",
        "row": <1-based row index from top, or null>,
        "horizontal_position": "left" | "center" | "right" | null,
        "bbox": {"x": <0-1 float>, "y": <0-1 float>, "w": <0-1 float>, "h": <0-1 float>},
        "business_impact": "<text>"
      }
    ],
    "extracted_prices": [
      {
        "text": "<raw price as visible, e.g. 'RON 15.99' or '-50% REDUCERE'>",
        "row": <1-based row index from top>,
        "horizontal_position": "left" | "center" | "right",
        "bbox": {"x": <0-1 float>, "y": <0-1 float>, "w": <0-1 float>, "h": <0-1 float>}
      }
    ],
    "suggestions": ["<actionable suggestion>"],
    "photo_quality": {"score": <0-100>, "notes": "<text>"},
    "rows": [
      {
        "name": "<row name>",
        "position": <int>,
        "status": "compliant" | "partial" | "non_compliant",
        "found_products": [{"sku": "<sku-or-null>", "name": "<name>", "qty": <int>}],
        "issues": ["<short issue strings>"]
      }
    ],
    "unauthorized_items": [{"name": "<name>", "row": <int>}],
    "extracted_products": [{"sku": "<sku-or-null>", "name": "<name>", "qty": <int>}]
  }

  Notes on issue types:
    * "missing_product" — a product that should be there is absent
    * "wrong_placement" — a product is present but on the wrong shelf
    * "wrong_qty" — facings count differs from expected
    * "out_of_stock" — empty slot where product should be
    * "unauthorized_item" — a product is on the shelf that isn't on the planogram
    * "photo_quality" — image issues (blur, glare, occlusion) affecting confidence
    * "mismatch" — catch-all for other discrepancies

  CRITICAL — BOUNDING BOXES:
    * Coordinates are NORMALIZED to the actual shelf photo (image 2 in
      two-image mode; the single image in one-image mode).
    * Origin (0, 0) is the TOP-LEFT corner of the visible photo.
      Bottom-right corner is (1, 1). Y INCREASES DOWNWARD.
    * (x, y) is the top-left corner of the box; (w, h) are width and
      height. All four values MUST be floats in [0.0, 1.0].
    * Calibration sanity-check before you respond: a label that should
      appear on the TOP shelf has y between ~0.05 and ~0.30. MIDDLE
      shelf is ~0.30 to ~0.65. BOTTOM shelf is ~0.65 to ~0.95. NEVER
      emit y > 0.95 — that area is the floor / store carpet, not a
      product zone. NEVER emit y < 0.0 — that's outside the image.
    * For a price tag specifically: the bbox should wrap JUST the price
      number itself (typically a tiny rectangle ~3-6% wide and ~2-3%
      tall on the shelf edge below the products), not the product zone
      above it. Center the bbox on the visible text.
    * For a missing/out-of-stock product: the bbox is the empty shelf
      GAP where the product belongs — typically about the size of one
      product facing.
    * Make boxes TIGHT. Don't inflate them to cover surrounding area.
    * NEVER emit the same `bbox` twice for the same physical element.
    * If you cannot determine a precise bbox, use `null`. Approximate
      row + horizontal_position are still required as fallback.

  Output ONLY the JSON. No prose. No code fences.
  """

  @doc "The active system prompt text. Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @doc """
  Build the vision Request.

  ## Args
    * `planogram` — map with `:name` and `:expected_rows`
    * `shelf_bytes` — binary, the actual shelf photo
    * `opts` — keyword:
      * `:reference_bytes` — optional binary, the reference planogram image.
        When given, included as the first image block.
      * `:scenario` — string for Mock keying. Default `"compliant"`.
      * `:max_tokens` — default 4096.
  """
  @spec build(map(), binary(), keyword()) :: Request.t()
  def build(planogram, shelf_bytes, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, "compliant")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    reference_bytes = Keyword.get(opts, :reference_bytes)

    content_blocks = build_content_blocks(planogram, shelf_bytes, reference_bytes)

    %Request{
      model: "claude-sonnet-4-5",
      system: @system_prompt,
      max_tokens: max_tokens,
      messages: [%{role: "user", content: content_blocks}],
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }
  end

  defp build_content_blocks(planogram, shelf_bytes, nil) do
    # Single-image mode: shelf photo + text description of expected layout
    [
      image_block(shelf_bytes),
      text_block(single_image_text(planogram))
    ]
  end

  defp build_content_blocks(planogram, shelf_bytes, reference_bytes)
       when is_binary(reference_bytes) do
    # Two-image mode: reference + shelf + comparison instructions
    [
      image_block(reference_bytes),
      image_block(shelf_bytes),
      text_block(two_image_text(planogram))
    ]
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

  defp two_image_text(%{name: name}) do
    """
    Image 1 (above): the REFERENCE planogram for "#{name}".
    Image 2 (above): the ACTUAL shelf photo to audit.

    Compare them visually. Identify mismatches, wrong placements, out-of-stock
    slots, and any unauthorized products. Extract every visible price tag from
    image 2. Return the JSON shape described in the system prompt.
    """
  end

  defp single_image_text(%{name: name, expected_rows: rows}) do
    """
    Reference planogram: "#{name}"

    Expected rows:
    #{Jason.encode!(rows, pretty: true)}

    The image attached above is a photo of the actual shelf. Audit
    compliance and return the JSON shape described in the system prompt.
    """
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
