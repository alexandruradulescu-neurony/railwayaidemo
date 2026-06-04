defmodule Showcase.Planogram.Impl.ResultRendererTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.ResultRenderer

  describe "render/1" do
    test "maps a full result to view-model" do
      raw = %{
        "compliance_score" => 87,
        "executive_summary" => "Shelf is mostly in order.",
        "rows" => [
          %{"name" => "Top", "position" => 1, "status" => "compliant",
            "found_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}],
            "issues" => []}
        ],
        "issues" => [
          %{"type" => "missing_product", "severity" => "medium",
            "description" => "Sprite missing", "business_impact" => "Lost sales"}
        ],
        "unauthorized_items" => [],
        "suggestions" => ["Restock Sprite"],
        "photo_quality" => %{"score" => 95, "notes" => "Clear photo"},
        "extracted_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]
      }

      vm = ResultRenderer.render(raw)
      assert vm.gauge_pct == 87
      assert vm.executive_summary == "Shelf is mostly in order."
      assert length(vm.rows) == 1
      assert hd(vm.rows).name == "Top"
      assert hd(vm.rows).status_color == "emerald"
      assert length(vm.issues) == 1
      assert hd(vm.issues).severity_color == "amber"
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
      assert vm.suggestions == []
      assert vm.photo_quality == %{score: nil, notes: nil}
      assert vm.extracted_products == []
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

    test "clamps gauge to 0-100 range" do
      assert ResultRenderer.render(%{"compliance_score" => 120}).gauge_pct == 100
      assert ResultRenderer.render(%{"compliance_score" => -5}).gauge_pct == 0
      assert ResultRenderer.render(%{"compliance_score" => "bad"}).gauge_pct == 0
    end
  end
end
