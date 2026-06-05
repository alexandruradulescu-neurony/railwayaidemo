defmodule Showcase.Planogram.MockPrompts do
  @moduledoc """
  Canned scenarios registered on `AnthropicClient.Mock`. Three scenarios:
  `compliant`, `minor_issues`, `major_issues`.

  Each scenario returns a strict-JSON string matching the schema in
  `Impl.VisionRequest`'s system prompt.
  """

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.Planogram.Impl.VisionRequest

  @spec register_all() :: :ok
  def register_all do
    Mock.reset()

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

  defp scenarios do
    [
      {"compliant", compliant_json(), %{input_tokens: 2400, output_tokens: 380, cost_estimate_cents: 1.29}},
      {"minor_issues", minor_issues_json(), %{input_tokens: 2400, output_tokens: 520, cost_estimate_cents: 1.50}},
      {"major_issues", major_issues_json(), %{input_tokens: 2400, output_tokens: 700, cost_estimate_cents: 1.77}}
    ]
  end

  defp compliant_json do
    Jason.encode!(%{
      compliance_score: 96,
      executive_summary: "Shelf matches planogram. All rows compliant; product facings within tolerance.",
      rows: [
        %{name: "Top shelf", position: 1, status: "compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 6}], issues: []},
        %{name: "Middle shelf", position: 2, status: "compliant",
          found_products: [%{sku: "S2", name: "Sprite 500ml", qty: 5}, %{sku: "S3", name: "Fanta 500ml", qty: 4}], issues: []},
        %{name: "Bottom shelf", position: 3, status: "compliant",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}], issues: []}
      ],
      issues: [],
      unauthorized_items: [],
      suggestions: ["Shelf is in good state — no action needed."],
      photo_quality: %{score: 95, notes: "Sharp focus, good lighting."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 6},
        %{sku: "S2", name: "Sprite 500ml", qty: 5},
        %{sku: "S3", name: "Fanta 500ml", qty: 4},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end

  defp minor_issues_json do
    Jason.encode!(%{
      compliance_score: 78,
      executive_summary: "Shelf is mostly compliant. Two minor issues: Sprite is 1 facing under quota; Pepsi label is partially obscured.",
      rows: [
        %{name: "Top shelf", position: 1, status: "compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 6}], issues: []},
        %{name: "Middle shelf", position: 2, status: "partial",
          found_products: [%{sku: "S2", name: "Sprite 500ml", qty: 4}, %{sku: "S3", name: "Fanta 500ml", qty: 4}],
          issues: ["Sprite is 1 facing under quota (expected 5, found 4)."]},
        %{name: "Bottom shelf", position: 3, status: "partial",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}],
          issues: ["Pepsi label is partially obscured by promotional sticker."]}
      ],
      issues: [
        %{type: "wrong_qty", severity: "medium",
          description: "Sprite under-stocked on middle shelf (4 vs expected 5).",
          business_impact: "~10% lost facings → estimated 3-5% velocity drop on this SKU."},
        %{type: "photo_quality", severity: "low",
          description: "Promotional sticker partially covering Pepsi label on bottom shelf.",
          business_impact: "Cosmetic — does not affect compliance scoring."}
      ],
      unauthorized_items: [],
      suggestions: ["Restock 1 facing of Sprite 500ml on middle shelf.", "Remove or relocate the promotional sticker on bottom shelf."],
      photo_quality: %{score: 90, notes: "Good lighting, mild glare on bottom shelf."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 6},
        %{sku: "S2", name: "Sprite 500ml", qty: 4},
        %{sku: "S3", name: "Fanta 500ml", qty: 4},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end

  defp major_issues_json do
    Jason.encode!(%{
      compliance_score: 32,
      executive_summary: "Shelf is significantly non-compliant. Sprite missing entirely, unauthorized energy drinks on top shelf, Fanta short-stocked.",
      rows: [
        %{name: "Top shelf", position: 1, status: "non_compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 4}, %{sku: "X1", name: "Red Bull 250ml", qty: 3}],
          issues: ["Coca-Cola under-stocked (4 vs 6).", "Unauthorized: Red Bull 250ml not on planogram."]},
        %{name: "Middle shelf", position: 2, status: "non_compliant",
          found_products: [%{sku: "S3", name: "Fanta 500ml", qty: 2}],
          issues: ["Sprite 500ml MISSING (expected 5, found 0).", "Fanta short-stocked (2 vs 4)."]},
        %{name: "Bottom shelf", position: 3, status: "compliant",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}], issues: []}
      ],
      issues: [
        %{type: "missing_product", severity: "high",
          description: "Sprite 500ml entirely missing from middle shelf (expected 5 facings).",
          business_impact: "Major — Sprite is a top-10 SKU; full out-of-stock event."},
        %{type: "unauthorized_item", severity: "high",
          description: "Red Bull 250ml present on top shelf — not on planogram for this store class.",
          business_impact: "Planogram drift; potential cannibalization of authorized SKUs."},
        %{type: "wrong_qty", severity: "medium",
          description: "Coca-Cola 500ml under-stocked (4 vs expected 6).",
          business_impact: "~33% facing loss on flagship SKU."},
        %{type: "wrong_qty", severity: "medium",
          description: "Fanta 500ml under-stocked (2 vs expected 4).",
          business_impact: "Visible gap; reduced category share-of-shelf."}
      ],
      unauthorized_items: [%{name: "Red Bull 250ml", row: 1}],
      suggestions: [
        "Immediate restock: 5 facings of Sprite 500ml on middle shelf.",
        "Remove Red Bull 250ml from top shelf — not authorized for this planogram.",
        "Restock 2 facings Coca-Cola 500ml + 2 facings Fanta 500ml."
      ],
      photo_quality: %{score: 88, notes: "Adequate."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 4},
        %{sku: "X1", name: "Red Bull 250ml", qty: 3},
        %{sku: "S3", name: "Fanta 500ml", qty: 2},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end
end
