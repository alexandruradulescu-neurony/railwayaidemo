defmodule Showcase.InvoiceApproval.MockPrompts do
  @moduledoc """
  Curated scenarios for the Invoice Approval demo. Each entry:
    * `name` — scenario id used as both Mock fingerprint scenario AND
      DocumentBundle.scenario field.
    * `kind` — coarse label ("clean" | "qty_mismatch" | "price_drift" | ...).
    * `client_name` — for Seed → matches a seeded client.
    * `contract_name` — matches a seeded contract.
    * `delivery_notes` / `invoice` — JSONB content stored on the bundle.
    * `thresholds` — per-bundle threshold defaults.
    * `claude_response` — canned LLM response. Returns
      `{"raw_matrix": [...rows of raw discrepancies...], "summary": "..."}`
      so `Pipeline` can parse it through `ResilientJSONParser`.
  """

  @scenarios [
    %{
      name: "clean_match",
      kind: "clean",
      client_name: "Acme Industries",
      contract_name: "Q2 2026 Hardware Order",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "delivered_on" => "2026-05-15"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "due_date" => "2026-06-15"}
        ],
        "total" => 1000.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "WGT-001", "contract": {"qty": 100, "unit_price": 10.0}, "delivery": {"qty": 100, "unit_price": 10.0}, "invoice": {"qty": 100, "unit_price": 10.0}, "discrepancies": []}], "summary": "All values match exactly."})
    },
    %{
      name: "price_drift",
      kind: "price_drift",
      client_name: "Beta Distribution",
      contract_name: "Standing PO 2026",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "BLT-M8", "qty" => 500, "unit_price" => 0.42, "delivered_on" => "2026-05-20"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "BLT-M8", "qty" => 500, "unit_price" => 0.45, "due_date" => "2026-06-20"}
        ],
        "total" => 225.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "BLT-M8", "contract": {"qty": 500, "unit_price": 0.42}, "delivery": {"qty": 500, "unit_price": 0.42}, "invoice": {"qty": 500, "unit_price": 0.45}, "discrepancies": [{"field": "unit_price", "contract_value": 0.42, "delivery_value": 0.42, "invoice_value": 0.45, "diff_value": 7.14, "diff_basis": "pct"}]}], "summary": "Invoice unit price is 7.14% higher than contract for BLT-M8."})
    },
    %{
      name: "qty_mismatch",
      kind: "qty_mismatch",
      client_name: "Gamma Engineering",
      contract_name: "2026 Hinges Frame",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "HNG-001", "qty" => 200, "unit_price" => 3.0, "delivered_on" => "2026-05-25"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "HNG-001", "qty" => 220, "unit_price" => 3.0, "due_date" => "2026-06-25"}
        ],
        "total" => 660.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "HNG-001", "contract": {"qty": 200, "unit_price": 3.0}, "delivery": {"qty": 200, "unit_price": 3.0}, "invoice": {"qty": 220, "unit_price": 3.0}, "discrepancies": [{"field": "quantity", "contract_value": 200, "delivery_value": 200, "invoice_value": 220, "diff_value": 10.0, "diff_basis": "pct"}]}], "summary": "Invoice quantity is 10% higher than delivered for HNG-001."})
    },
    %{
      name: "out_of_contract",
      kind: "out_of_contract",
      client_name: "Acme Industries",
      contract_name: "Q2 2026 Hardware Order",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "delivered_on" => "2026-05-15"},
          %{"line_key" => "EXTRA-99", "qty" => 5, "unit_price" => 99.0, "delivered_on" => "2026-05-15"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "due_date" => "2026-06-15"},
          %{"line_key" => "EXTRA-99", "qty" => 5, "unit_price" => 99.0, "due_date" => "2026-06-15"}
        ],
        "total" => 1495.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "WGT-001", "contract": {"qty": 100, "unit_price": 10.0}, "delivery": {"qty": 100, "unit_price": 10.0}, "invoice": {"qty": 100, "unit_price": 10.0}, "discrepancies": []}, {"line_key": "EXTRA-99", "contract": null, "delivery": {"qty": 5, "unit_price": 99.0}, "invoice": {"qty": 5, "unit_price": 99.0}, "discrepancies": [{"field": "sku_not_in_contract", "contract_value": null, "delivery_value": 5, "invoice_value": 5, "diff_value": 0.0, "diff_basis": "absolute"}]}], "summary": "Line EXTRA-99 is not in the contract."})
    }
  ]

  def scenarios, do: @scenarios
end
