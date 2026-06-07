defmodule Showcase.Planogram.Impl.ResultRendererTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.ResultRenderer

  describe "render/1" do
    test "maps a full result to view-model — including extracted_prices + counts" do
      raw = %{
        "compliance_score" => 87,
        "executive_summary" => "Shelf is mostly in order.",
        "issues" => [
          %{"type" => "missing_product", "severity" => "medium",
            "description" => "Sprite missing", "business_impact" => "Lost sales",
            "row" => 2, "horizontal_position" => "left"},
          %{"type" => "out_of_stock", "severity" => "low",
            "description" => "Empty slot", "row" => 3, "horizontal_position" => "right"}
        ],
        "extracted_prices" => [
          %{"text" => "RON 15.99", "row" => 1, "horizontal_position" => "left"},
          %{"text" => "RON 8.50", "row" => 2, "horizontal_position" => "center"}
        ],
        "rows" => [
          %{"name" => "Top", "position" => 1, "status" => "compliant",
            "found_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}],
            "issues" => []}
        ],
        "unauthorized_items" => [],
        "suggestions" => ["Restock Sprite"],
        "photo_quality" => %{"score" => 95, "notes" => "Clear photo"},
        "extracted_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]
      }

      vm = ResultRenderer.render(raw)

      assert vm.gauge_pct == 87
      assert vm.executive_summary == "Shelf is mostly in order."
      assert length(vm.issues) == 2

      first_issue = hd(vm.issues)
      assert first_issue.row == 2
      assert first_issue.horizontal_position == "left"
      assert first_issue.severity_color == "amber"
      assert first_issue.badge == "MISSING"

      assert length(vm.extracted_prices) == 2
      assert hd(vm.extracted_prices).text == "RON 15.99"

      # Derived counts
      assert vm.mismatches_count == 1  # only missing_product counts
      assert vm.out_of_stock_count == 1
      assert vm.prices_count == 2

      assert vm.suggestions == ["Restock Sprite"]
      assert vm.photo_quality.score == 95
      refute vm.partial?
    end

    test "fills sensible defaults when fields are missing (:partial salvage)" do
      raw = %{"compliance_score" => 50, "rows" => []}
      vm = ResultRenderer.render(raw)

      assert vm.gauge_pct == 50
      assert vm.executive_summary == "(no summary returned)"
      assert vm.rows == []
      assert vm.issues == []
      assert vm.extracted_prices == []
      assert vm.suggestions == []
      assert vm.photo_quality == %{score: nil, notes: nil}
      assert vm.mismatches_count == 0
      assert vm.prices_count == 0
      assert vm.partial?
    end

    test "color codes row status" do
      assert ResultRenderer.row_status_color("compliant") == "emerald"
      assert ResultRenderer.row_status_color("partial") == "amber"
      assert ResultRenderer.row_status_color("non_compliant") == "rose"
      assert ResultRenderer.row_status_color("anything-else") == "zinc"
    end

    test "color codes issue severity" do
      assert ResultRenderer.severity_color("low") == "zinc"
      assert ResultRenderer.severity_color("medium") == "amber"
      assert ResultRenderer.severity_color("high") == "rose"
      assert ResultRenderer.severity_color(nil) == "zinc"
    end

    test "issue_badge/1 maps each known type to a label" do
      assert ResultRenderer.issue_badge("missing_product") == "MISSING"
      assert ResultRenderer.issue_badge("wrong_placement") == "WRONG PLACEMENT"
      assert ResultRenderer.issue_badge("out_of_stock") == "OUT OF STOCK"
      assert ResultRenderer.issue_badge("unauthorized_item") == "UNAUTHORIZED"
      assert ResultRenderer.issue_badge("mismatch") == "MISMATCH"
      assert ResultRenderer.issue_badge("photo_quality") == "PHOTO QUALITY"
      assert ResultRenderer.issue_badge("wrong_qty") == "WRONG QTY"
      assert ResultRenderer.issue_badge("anything-else") == "ISSUE"
    end

    test "clamps gauge to 0-100 range" do
      assert ResultRenderer.render(%{"compliance_score" => 120}).gauge_pct == 100
      assert ResultRenderer.render(%{"compliance_score" => -5}).gauge_pct == 0
      assert ResultRenderer.render(%{"compliance_score" => "bad"}).gauge_pct == 0
    end

    test "tolerates type-malformed fields without crashing" do
      raw = %{
        "compliance_score" => 50,
        "rows" => "oops-not-a-list",
        "issues" => 42,
        "extracted_prices" => "still bad",
        "unauthorized_items" => %{"key" => "value"},
        "suggestions" => nil,
        "photo_quality" => "not-a-map",
        "extracted_products" => true,
        "executive_summary" => ["not", "a", "string"]
      }

      vm = ResultRenderer.render(raw)
      assert vm.rows == []
      assert vm.issues == []
      assert vm.extracted_prices == []
      assert vm.unauthorized_items == []
      assert vm.suggestions == []
      assert vm.photo_quality == %{score: nil, notes: nil}
      assert vm.extracted_products == []
      assert vm.executive_summary == "(no summary returned)"
      assert vm.mismatches_count == 0
      assert vm.prices_count == 0
    end

    test "tolerates non-map row entries without crashing" do
      raw = %{"rows" => ["bad-row-as-string", 42, nil, %{"name" => "Real row"}]}
      vm = ResultRenderer.render(raw)
      assert length(vm.rows) == 4
      assert Enum.at(vm.rows, 3).name == "Real row"
      assert Enum.at(vm.rows, 0).name == "(unnamed row)"
    end

    test "render/1 with non-map input returns the default-laden empty result" do
      vm = ResultRenderer.render("not a map")
      assert vm.gauge_pct == 0
      assert vm.rows == []
      assert vm.partial?
    end
  end
end
