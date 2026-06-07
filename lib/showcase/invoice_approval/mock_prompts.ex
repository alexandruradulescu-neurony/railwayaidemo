defmodule Showcase.InvoiceApproval.MockPrompts do
  @moduledoc """
  Curated scenarios for the Invoice Approval demo. Each entry models a
  real-world Romanian commercial cycle:

    * **Contract** (signed agreement on file, attached to the client) →
      `contract_items` — the canonical prices/quantities the supplier
      committed to.
    * **Aviz de însoțire a mărfii** (delivery note that ships with the
      goods) → `delivery_notes` JSONB, items list mirrors the contract.
    * **Factura** (invoice that arrives separately by email) → `invoice`
      JSONB. The clerk reconciles the three.

  Demo scenarios are tied to the **shared client roster** (Meesenburg
  Romania, Alexandru Erdei, Dragos Manolache) so the whole showcase tells
  one story: orders come into OrderFlow from these same clients, and
  later their invoices arrive into Invoice Approval.

  Each entry is rich enough (5-6 line items in Romanian feronerie) for the
  rendered "PDF" documents to look like real Romanian commercial paperwork.

  `claude_response` is the scripted JSON the pipeline parses for this
  scenario — bypasses real Claude so the demo stays predictable.
  """

  @scenarios [
    # ── Scenario 1: clean match ─────────────────────────────────────────
    %{
      name: "clean_match",
      kind: "clean",
      client_name: "Meesenburg Romania",
      contract_name: "Contract-cadru feronerie 2026",
      contract_items: [
        %{"sku" => "K1001-07-n03", "name" => "Mâner ușă AXOR alb 28x92", "qty" => 100, "unit_price" => 25.50},
        %{"sku" => "K1001-11-n03", "name" => "Mâner ușă AXOR maro 28x92", "qty" => 50, "unit_price" => 25.50},
        %{"sku" => "K3001-01-n03", "name" => "Colțar jos K1", "qty" => 200, "unit_price" => 8.20},
        %{"sku" => "BAL-USA-MARO", "name" => "Balamale ușă maro", "qty" => 30, "unit_price" => 45.00},
        %{"sku" => "BIT-PH2-BOX", "name" => "Biți PH2 (cutie 20 buc)", "qty" => 20, "unit_price" => 18.00}
      ],
      delivery_notes: %{
        "aviz_number" => "AVZ-2026-001",
        "delivery_date" => "2026-05-15",
        "items" => [
          %{"line_key" => "K1001-07-n03", "qty" => 100, "unit_price" => 25.50, "delivered_on" => "2026-05-15"},
          %{"line_key" => "K1001-11-n03", "qty" => 50, "unit_price" => 25.50, "delivered_on" => "2026-05-15"},
          %{"line_key" => "K3001-01-n03", "qty" => 200, "unit_price" => 8.20, "delivered_on" => "2026-05-15"},
          %{"line_key" => "BAL-USA-MARO", "qty" => 30, "unit_price" => 45.00, "delivered_on" => "2026-05-15"},
          %{"line_key" => "BIT-PH2-BOX", "qty" => 20, "unit_price" => 18.00, "delivered_on" => "2026-05-15"}
        ]
      },
      invoice: %{
        "invoice_number" => "F-2026-1042",
        "issue_date" => "2026-05-20",
        "due_date" => "2026-06-20",
        "items" => [
          %{"line_key" => "K1001-07-n03", "qty" => 100, "unit_price" => 25.50, "due_date" => "2026-06-20"},
          %{"line_key" => "K1001-11-n03", "qty" => 50, "unit_price" => 25.50, "due_date" => "2026-06-20"},
          %{"line_key" => "K3001-01-n03", "qty" => 200, "unit_price" => 8.20, "due_date" => "2026-06-20"},
          %{"line_key" => "BAL-USA-MARO", "qty" => 30, "unit_price" => 45.00, "due_date" => "2026-06-20"},
          %{"line_key" => "BIT-PH2-BOX", "qty" => 20, "unit_price" => 18.00, "due_date" => "2026-06-20"}
        ],
        "total" => 6175.00
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [
        {"line_key": "K1001-07-n03", "contract": {"qty": 100, "unit_price": 25.50}, "delivery": {"qty": 100, "unit_price": 25.50}, "invoice": {"qty": 100, "unit_price": 25.50}, "discrepancies": []},
        {"line_key": "K1001-11-n03", "contract": {"qty": 50, "unit_price": 25.50}, "delivery": {"qty": 50, "unit_price": 25.50}, "invoice": {"qty": 50, "unit_price": 25.50}, "discrepancies": []},
        {"line_key": "K3001-01-n03", "contract": {"qty": 200, "unit_price": 8.20}, "delivery": {"qty": 200, "unit_price": 8.20}, "invoice": {"qty": 200, "unit_price": 8.20}, "discrepancies": []},
        {"line_key": "BAL-USA-MARO", "contract": {"qty": 30, "unit_price": 45.00}, "delivery": {"qty": 30, "unit_price": 45.00}, "invoice": {"qty": 30, "unit_price": 45.00}, "discrepancies": []},
        {"line_key": "BIT-PH2-BOX", "contract": {"qty": 20, "unit_price": 18.00}, "delivery": {"qty": 20, "unit_price": 18.00}, "invoice": {"qty": 20, "unit_price": 18.00}, "discrepancies": []}
      ], "summary": "All 5 lines match contract, delivery, and invoice."})
    },

    # ── Scenario 2: price drift on one line ─────────────────────────────
    %{
      name: "price_drift",
      kind: "price_drift",
      client_name: "Alexandru Erdei",
      contract_name: "Acord furnizare cremoane 2026",
      contract_items: [
        %{"sku" => "K2001-06-n03", "name" => "Broască multipunct ac. mâner", "qty" => 50, "unit_price" => 120.00},
        %{"sku" => "K5001-13-n03", "name" => "Cremon ușă tip K", "qty" => 30, "unit_price" => 95.00},
        %{"sku" => "COLT-JOS", "name" => "Colțar jos universal", "qty" => 100, "unit_price" => 8.20},
        %{"sku" => "BAL-ANTIFL", "name" => "Balamale antiflambaj 4-toc + ccv", "qty" => 20, "unit_price" => 35.00},
        %{"sku" => "MEC-OB-2400", "name" => "Mecanism OB 2000-2400", "qty" => 15, "unit_price" => 180.00}
      ],
      delivery_notes: %{
        "aviz_number" => "AVZ-2026-007",
        "delivery_date" => "2026-05-20",
        "items" => [
          %{"line_key" => "K2001-06-n03", "qty" => 50, "unit_price" => 120.00, "delivered_on" => "2026-05-20"},
          %{"line_key" => "K5001-13-n03", "qty" => 30, "unit_price" => 95.00, "delivered_on" => "2026-05-20"},
          %{"line_key" => "COLT-JOS", "qty" => 100, "unit_price" => 8.20, "delivered_on" => "2026-05-20"},
          %{"line_key" => "BAL-ANTIFL", "qty" => 20, "unit_price" => 35.00, "delivered_on" => "2026-05-20"},
          %{"line_key" => "MEC-OB-2400", "qty" => 15, "unit_price" => 180.00, "delivered_on" => "2026-05-20"}
        ]
      },
      invoice: %{
        "invoice_number" => "F-2026-1187",
        "issue_date" => "2026-05-25",
        "due_date" => "2026-06-25",
        "items" => [
          # K2001-06 invoiced at 128.40 vs contracted 120.00 — +7%
          %{"line_key" => "K2001-06-n03", "qty" => 50, "unit_price" => 128.40, "due_date" => "2026-06-25"},
          %{"line_key" => "K5001-13-n03", "qty" => 30, "unit_price" => 95.00, "due_date" => "2026-06-25"},
          %{"line_key" => "COLT-JOS", "qty" => 100, "unit_price" => 8.20, "due_date" => "2026-06-25"},
          %{"line_key" => "BAL-ANTIFL", "qty" => 20, "unit_price" => 35.00, "due_date" => "2026-06-25"},
          %{"line_key" => "MEC-OB-2400", "qty" => 15, "unit_price" => 180.00, "due_date" => "2026-06-25"}
        ],
        "total" => 13290.00
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [
        {"line_key": "K2001-06-n03", "contract": {"qty": 50, "unit_price": 120.00}, "delivery": {"qty": 50, "unit_price": 120.00}, "invoice": {"qty": 50, "unit_price": 128.40}, "discrepancies": [{"field": "unit_price", "contract_value": 120.00, "delivery_value": 120.00, "invoice_value": 128.40, "diff_value": 7.0, "diff_basis": "pct"}]},
        {"line_key": "K5001-13-n03", "contract": {"qty": 30, "unit_price": 95.00}, "delivery": {"qty": 30, "unit_price": 95.00}, "invoice": {"qty": 30, "unit_price": 95.00}, "discrepancies": []},
        {"line_key": "COLT-JOS", "contract": {"qty": 100, "unit_price": 8.20}, "delivery": {"qty": 100, "unit_price": 8.20}, "invoice": {"qty": 100, "unit_price": 8.20}, "discrepancies": []},
        {"line_key": "BAL-ANTIFL", "contract": {"qty": 20, "unit_price": 35.00}, "delivery": {"qty": 20, "unit_price": 35.00}, "invoice": {"qty": 20, "unit_price": 35.00}, "discrepancies": []},
        {"line_key": "MEC-OB-2400", "contract": {"qty": 15, "unit_price": 180.00}, "delivery": {"qty": 15, "unit_price": 180.00}, "invoice": {"qty": 15, "unit_price": 180.00}, "discrepancies": []}
      ], "summary": "K2001-06-n03 invoice price is 7% above contracted price. All other lines clean."})
    },

    # ── Scenario 3: quantity over-billing ───────────────────────────────
    %{
      name: "qty_mismatch",
      kind: "qty_mismatch",
      client_name: "Dragos Manolache",
      contract_name: "Contract balamale Q2 2026",
      contract_items: [
        %{"sku" => "BAL-USA-MARO", "name" => "Balamale ușă maro", "qty" => 200, "unit_price" => 45.00},
        %{"sku" => "K3001-07-n03", "name" => "Colțar prag aluminiu", "qty" => 50, "unit_price" => 12.00},
        %{"sku" => "COLT-CIU", "name" => "Colțar cu ciupercă", "qty" => 80, "unit_price" => 9.50},
        %{"sku" => "K4001-03-n03", "name" => "Mecanism antiflambaj 4-toc + ccv", "qty" => 25, "unit_price" => 220.00},
        %{"sku" => "PRL-1E-400", "name" => "Prelungitor 1E fără cuplă 400mv", "qty" => 30, "unit_price" => 28.00}
      ],
      delivery_notes: %{
        "aviz_number" => "AVZ-2026-013",
        "delivery_date" => "2026-05-25",
        "items" => [
          %{"line_key" => "BAL-USA-MARO", "qty" => 200, "unit_price" => 45.00, "delivered_on" => "2026-05-25"},
          %{"line_key" => "K3001-07-n03", "qty" => 50, "unit_price" => 12.00, "delivered_on" => "2026-05-25"},
          %{"line_key" => "COLT-CIU", "qty" => 80, "unit_price" => 9.50, "delivered_on" => "2026-05-25"},
          %{"line_key" => "K4001-03-n03", "qty" => 25, "unit_price" => 220.00, "delivered_on" => "2026-05-25"},
          %{"line_key" => "PRL-1E-400", "qty" => 30, "unit_price" => 28.00, "delivered_on" => "2026-05-25"}
        ]
      },
      invoice: %{
        "invoice_number" => "F-2026-1305",
        "issue_date" => "2026-05-30",
        "due_date" => "2026-06-30",
        "items" => [
          # 220 billed but only 200 delivered — 10% over
          %{"line_key" => "BAL-USA-MARO", "qty" => 220, "unit_price" => 45.00, "due_date" => "2026-06-30"},
          %{"line_key" => "K3001-07-n03", "qty" => 50, "unit_price" => 12.00, "due_date" => "2026-06-30"},
          %{"line_key" => "COLT-CIU", "qty" => 80, "unit_price" => 9.50, "due_date" => "2026-06-30"},
          %{"line_key" => "K4001-03-n03", "qty" => 25, "unit_price" => 220.00, "due_date" => "2026-06-30"},
          %{"line_key" => "PRL-1E-400", "qty" => 30, "unit_price" => 28.00, "due_date" => "2026-06-30"}
        ],
        "total" => 16170.00
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [
        {"line_key": "BAL-USA-MARO", "contract": {"qty": 200, "unit_price": 45.00}, "delivery": {"qty": 200, "unit_price": 45.00}, "invoice": {"qty": 220, "unit_price": 45.00}, "discrepancies": [{"field": "quantity", "contract_value": 200, "delivery_value": 200, "invoice_value": 220, "diff_value": 10.0, "diff_basis": "pct"}]},
        {"line_key": "K3001-07-n03", "contract": {"qty": 50, "unit_price": 12.00}, "delivery": {"qty": 50, "unit_price": 12.00}, "invoice": {"qty": 50, "unit_price": 12.00}, "discrepancies": []},
        {"line_key": "COLT-CIU", "contract": {"qty": 80, "unit_price": 9.50}, "delivery": {"qty": 80, "unit_price": 9.50}, "invoice": {"qty": 80, "unit_price": 9.50}, "discrepancies": []},
        {"line_key": "K4001-03-n03", "contract": {"qty": 25, "unit_price": 220.00}, "delivery": {"qty": 25, "unit_price": 220.00}, "invoice": {"qty": 25, "unit_price": 220.00}, "discrepancies": []},
        {"line_key": "PRL-1E-400", "contract": {"qty": 30, "unit_price": 28.00}, "delivery": {"qty": 30, "unit_price": 28.00}, "invoice": {"qty": 30, "unit_price": 28.00}, "discrepancies": []}
      ], "summary": "Invoice bills 220 of BAL-USA-MARO but only 200 were delivered — 10% over."})
    },

    # ── Scenario 4: line not in contract ─────────────────────────────────
    %{
      name: "out_of_contract",
      kind: "out_of_contract",
      client_name: "Meesenburg Romania",
      contract_name: "Contract-cadru feronerie 2026",
      contract_items: [
        %{"sku" => "K1001-07-n03", "name" => "Mâner ușă AXOR alb 28x92", "qty" => 100, "unit_price" => 25.50},
        %{"sku" => "BAL-USA-MARO", "name" => "Balamale ușă maro", "qty" => 50, "unit_price" => 45.00},
        %{"sku" => "COLT-JOS", "name" => "Colțar jos universal", "qty" => 80, "unit_price" => 8.20},
        %{"sku" => "BIT-PH2-BOX", "name" => "Biți PH2 (cutie 20 buc)", "qty" => 30, "unit_price" => 18.00}
      ],
      delivery_notes: %{
        "aviz_number" => "AVZ-2026-019",
        "delivery_date" => "2026-06-01",
        "items" => [
          %{"line_key" => "K1001-07-n03", "qty" => 100, "unit_price" => 25.50, "delivered_on" => "2026-06-01"},
          %{"line_key" => "BAL-USA-MARO", "qty" => 50, "unit_price" => 45.00, "delivered_on" => "2026-06-01"},
          %{"line_key" => "COLT-JOS", "qty" => 80, "unit_price" => 8.20, "delivered_on" => "2026-06-01"},
          %{"line_key" => "BIT-PH2-BOX", "qty" => 30, "unit_price" => 18.00, "delivered_on" => "2026-06-01"},
          # Snuck onto the delivery + invoice but never on the contract
          %{"line_key" => "EXTRA-LMP-LED", "qty" => 5, "unit_price" => 99.00, "delivered_on" => "2026-06-01"}
        ]
      },
      invoice: %{
        "invoice_number" => "F-2026-1411",
        "issue_date" => "2026-06-05",
        "due_date" => "2026-07-05",
        "items" => [
          %{"line_key" => "K1001-07-n03", "qty" => 100, "unit_price" => 25.50, "due_date" => "2026-07-05"},
          %{"line_key" => "BAL-USA-MARO", "qty" => 50, "unit_price" => 45.00, "due_date" => "2026-07-05"},
          %{"line_key" => "COLT-JOS", "qty" => 80, "unit_price" => 8.20, "due_date" => "2026-07-05"},
          %{"line_key" => "BIT-PH2-BOX", "qty" => 30, "unit_price" => 18.00, "due_date" => "2026-07-05"},
          %{"line_key" => "EXTRA-LMP-LED", "qty" => 5, "unit_price" => 99.00, "due_date" => "2026-07-05"}
        ],
        "total" => 6661.00
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [
        {"line_key": "K1001-07-n03", "contract": {"qty": 100, "unit_price": 25.50}, "delivery": {"qty": 100, "unit_price": 25.50}, "invoice": {"qty": 100, "unit_price": 25.50}, "discrepancies": []},
        {"line_key": "BAL-USA-MARO", "contract": {"qty": 50, "unit_price": 45.00}, "delivery": {"qty": 50, "unit_price": 45.00}, "invoice": {"qty": 50, "unit_price": 45.00}, "discrepancies": []},
        {"line_key": "COLT-JOS", "contract": {"qty": 80, "unit_price": 8.20}, "delivery": {"qty": 80, "unit_price": 8.20}, "invoice": {"qty": 80, "unit_price": 8.20}, "discrepancies": []},
        {"line_key": "BIT-PH2-BOX", "contract": {"qty": 30, "unit_price": 18.00}, "delivery": {"qty": 30, "unit_price": 18.00}, "invoice": {"qty": 30, "unit_price": 18.00}, "discrepancies": []},
        {"line_key": "EXTRA-LMP-LED", "contract": null, "delivery": {"qty": 5, "unit_price": 99.00}, "invoice": {"qty": 5, "unit_price": 99.00}, "discrepancies": [{"field": "sku_not_in_contract", "contract_value": null, "delivery_value": 5, "invoice_value": 5, "diff_value": 0.0, "diff_basis": "absolute"}]}
      ], "summary": "Line EXTRA-LMP-LED appears on delivery + invoice but is not in the contract."})
    }
  ]

  def scenarios, do: @scenarios

  @doc """
  Look up the scripted Claude response text for a given scenario.

  Lets `Pipeline.process_bundle/2` bypass real Claude for the seeded demo
  bundles, so the AE always sees the same predictable verdict regardless
  of which AnthropicClient impl is configured. Returns `{:ok, text}` or
  `:not_found`.
  """
  @spec scripted_response_for(String.t() | nil) :: {:ok, String.t()} | :not_found
  def scripted_response_for(nil), do: :not_found

  def scripted_response_for(name) when is_binary(name) do
    case Enum.find(@scenarios, &(&1.name == name)) do
      nil -> :not_found
      s -> {:ok, s.claude_response}
    end
  end

  @doc """
  Pull a scenario by name for the Seed loop. Returns `nil` when not found.
  """
  @spec find_scenario(String.t()) :: map() | nil
  def find_scenario(name) when is_binary(name) do
    Enum.find(@scenarios, &(&1.name == name))
  end
end
