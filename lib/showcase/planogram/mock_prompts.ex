defmodule Showcase.Planogram.MockPrompts do
  @moduledoc """
  Canned scenarios registered on `AnthropicClient.Mock`. Three scenarios:
  `compliant`, `minor_issues`, `major_issues`.

  Each scenario returns a strict-JSON string matching the schema in
  `Impl.VisionRequest`'s system prompt. Scenarios include:

    * `compliance_score` + `executive_summary`
    * `issues` with type (mismatch / out_of_stock / wrong_placement / ...),
      severity, row index, and horizontal position so the UI can anchor
      labels on the shelf photo
    * `extracted_prices` — every price tag the model "sees"
    * legacy `rows` / `extracted_products` for backward-compat
  """

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.Common.AnthropicClient.Types.{Response, Usage}
  alias Showcase.Planogram.Impl.VisionRequest

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

  Returns `:not_found` for any scenario not in the seeded set (e.g. a
  task created live via the Manager view).
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
       %{input_tokens: 2800, output_tokens: 520, cost_estimate_cents: 1.62}},
      {"minor_issues", minor_issues_json(),
       %{input_tokens: 2800, output_tokens: 720, cost_estimate_cents: 1.92}},
      {"major_issues", major_issues_json(),
       %{input_tokens: 2800, output_tokens: 950, cost_estimate_cents: 2.26}}
    ]
  end

  defp compliant_json do
    Jason.encode!(%{
      compliance_score: 96,
      executive_summary:
        "Shelf matches the reference planogram. All product blocks are in their expected positions; price tags are visible and within tolerance.",
      issues: [],
      extracted_prices: [
        %{text: "RON 15.99", row: 1, horizontal_position: "left"},
        %{text: "RON 12.50", row: 1, horizontal_position: "right"},
        %{text: "RON 8.50", row: 2, horizontal_position: "left"},
        %{text: "RON 8.50", row: 2, horizontal_position: "center"},
        %{text: "RON 9.99", row: 2, horizontal_position: "right"},
        %{text: "RON 15.99", row: 3, horizontal_position: "left"},
        %{text: "RON 4.20", row: 3, horizontal_position: "right"}
      ],
      suggestions: ["Shelf is in good state — no action needed."],
      photo_quality: %{score: 95, notes: "Sharp focus, good lighting."},
      rows: [
        %{name: "Top shelf", position: 1, status: "compliant",
          found_products: [%{sku: "S1", name: "Cereal A", qty: 6}], issues: []},
        %{name: "Middle shelf", position: 2, status: "compliant",
          found_products: [%{sku: "S2", name: "Cereal B", qty: 5}, %{sku: "S3", name: "Cereal C", qty: 4}], issues: []},
        %{name: "Bottom shelf", position: 3, status: "compliant",
          found_products: [%{sku: "S4", name: "Snack D", qty: 6}], issues: []}
      ],
      unauthorized_items: [],
      extracted_products: [
        %{sku: "S1", name: "Cereal A", qty: 6},
        %{sku: "S2", name: "Cereal B", qty: 5},
        %{sku: "S3", name: "Cereal C", qty: 4},
        %{sku: "S4", name: "Snack D", qty: 6}
      ]
    })
  end

  defp minor_issues_json do
    Jason.encode!(%{
      compliance_score: 85,
      executive_summary:
        "Shelf is mostly compliant. Detected: a wrong placement on the middle shelf and an out-of-stock slot on the bottom. Price tags all extracted cleanly.",
      issues: [
        %{
          type: "wrong_placement",
          severity: "medium",
          description: "Cereal B placed on top shelf — expected on middle shelf per planogram.",
          row: 1,
          horizontal_position: "center",
          business_impact: "Reduced visibility for the SKU; minor planogram drift."
        },
        %{
          type: "mismatch",
          severity: "medium",
          description: "Snack pack on middle shelf left position does not match reference.",
          row: 2,
          horizontal_position: "left",
          business_impact: "Visible category drift; impacts shopper flow."
        },
        %{
          type: "out_of_stock",
          severity: "low",
          description: "Empty slot on bottom shelf (left position) where Snack D should be.",
          row: 3,
          horizontal_position: "left",
          business_impact: "Lost-sale risk on a top-50 SKU until restocked."
        }
      ],
      extracted_prices: [
        %{text: "RON 15.99", row: 1, horizontal_position: "left"},
        %{text: "RON 12.50", row: 1, horizontal_position: "center"},
        %{text: "RON 8.50", row: 2, horizontal_position: "left"},
        %{text: "RON 8.50", row: 2, horizontal_position: "center"},
        %{text: "RON 9.99", row: 2, horizontal_position: "right"},
        %{text: "RON 15.99", row: 3, horizontal_position: "left"},
        %{text: "RON 4.20", row: 3, horizontal_position: "right"}
      ],
      suggestions: [
        "Move Cereal B from top shelf to middle shelf.",
        "Restock bottom-shelf left slot with Snack D."
      ],
      photo_quality: %{score: 90, notes: "Good lighting, mild glare on bottom shelf."},
      rows: [
        %{name: "Top shelf", position: 1, status: "partial",
          found_products: [%{sku: "S1", name: "Cereal A", qty: 6}, %{sku: "S2", name: "Cereal B (misplaced)", qty: 2}],
          issues: ["Cereal B misplaced from middle shelf."]},
        %{name: "Middle shelf", position: 2, status: "partial",
          found_products: [%{sku: "S3", name: "Cereal C", qty: 4}], issues: ["Cereal B missing from expected position."]},
        %{name: "Bottom shelf", position: 3, status: "partial",
          found_products: [%{sku: "S4", name: "Snack D", qty: 4}], issues: ["1 facing out of stock on left."]}
      ],
      unauthorized_items: [],
      extracted_products: [
        %{sku: "S1", name: "Cereal A", qty: 6},
        %{sku: "S2", name: "Cereal B", qty: 2},
        %{sku: "S3", name: "Cereal C", qty: 4},
        %{sku: "S4", name: "Snack D", qty: 4}
      ]
    })
  end

  defp major_issues_json do
    Jason.encode!(%{
      compliance_score: 42,
      executive_summary:
        "Significant deviation from planogram. 12 mismatches detected across all four rows, including two complete out-of-stock zones and an unauthorized energy drink display on the top shelf. Price tags still extracted, but layout requires immediate remediation.",
      issues: [
        %{type: "mismatch", severity: "high",
          description: "Top shelf left section has wrong product family (energy drinks vs expected cereal).",
          row: 1, horizontal_position: "left",
          business_impact: "Major category drift; shopper confusion."},
        %{type: "unauthorized_item", severity: "high",
          description: "Red Bull display on top shelf not approved for this store class.",
          row: 1, horizontal_position: "center",
          business_impact: "Unsanctioned brand presence; revenue accounting impact."},
        %{type: "out_of_stock", severity: "high",
          description: "Bottom shelf left section is empty.",
          row: 3, horizontal_position: "left",
          business_impact: "Lost-sale event across multiple SKUs."},
        %{type: "out_of_stock", severity: "medium",
          description: "Middle shelf right section empty — Cereal C absent.",
          row: 2, horizontal_position: "right",
          business_impact: "Top-10 SKU missing from secondary placement."},
        %{type: "wrong_placement", severity: "medium",
          description: "Cereal A bagged variant on middle shelf — should be boxed format on top.",
          row: 2, horizontal_position: "center",
          business_impact: "Wrong pack size visible to shoppers."},
        %{type: "wrong_qty", severity: "medium",
          description: "Snack D facings on bottom-right are 2 (expected 4).",
          row: 3, horizontal_position: "right",
          business_impact: "Visible gap; reduced share of shelf."}
      ],
      extracted_prices: [
        %{text: "RON 15.99", row: 1, horizontal_position: "left"},
        %{text: "RON 12.99", row: 1, horizontal_position: "right"},
        %{text: "RON 8.50", row: 2, horizontal_position: "left"},
        %{text: "RON 8.50", row: 2, horizontal_position: "center"},
        %{text: "RON 15.99", row: 3, horizontal_position: "left"},
        %{text: "RON 4.20", row: 3, horizontal_position: "center"},
        %{text: "RON 8.50", row: 3, horizontal_position: "right"}
      ],
      suggestions: [
        "Immediate: remove unauthorized Red Bull display from top shelf.",
        "Restock middle-right and bottom-left out-of-stock slots.",
        "Swap bagged Cereal A on middle for boxed format; relocate to top.",
        "Add 2 facings of Snack D on bottom-right."
      ],
      photo_quality: %{score: 88, notes: "Adequate — some glare on top row."},
      rows: [
        %{name: "Top shelf", position: 1, status: "non_compliant",
          found_products: [%{sku: "X1", name: "Red Bull 250ml", qty: 4}, %{sku: "S1", name: "Cereal A (boxed)", qty: 2}],
          issues: ["Energy drinks not on planogram.", "Cereal A under-stocked."]},
        %{name: "Middle shelf", position: 2, status: "non_compliant",
          found_products: [%{sku: "S1", name: "Cereal A (bagged)", qty: 3}],
          issues: ["Wrong pack format.", "Cereal C missing."]},
        %{name: "Bottom shelf", position: 3, status: "non_compliant",
          found_products: [%{sku: "S4", name: "Snack D", qty: 2}],
          issues: ["Left section empty.", "Snack D short-stocked."]}
      ],
      unauthorized_items: [%{name: "Red Bull 250ml", row: 1}],
      extracted_products: [
        %{sku: "X1", name: "Red Bull 250ml", qty: 4},
        %{sku: "S1", name: "Cereal A", qty: 5},
        %{sku: "S4", name: "Snack D", qty: 2}
      ]
    })
  end
end
