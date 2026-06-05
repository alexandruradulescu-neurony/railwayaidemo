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

    test "tolerates type-malformed fields without crashing" do
      # ResilientJSONParser :partial can drop fields mid-shape — a string
      # where a list was expected, a number where a map was expected, etc.
      # None of these should raise.
      raw = %{
        "compliance_score" => 50,
        "rows" => "oops-not-a-list",
        "issues" => 42,
        "unauthorized_items" => %{"key" => "value"},
        "suggestions" => nil,
        "photo_quality" => "not-a-map",
        "extracted_products" => true,
        "executive_summary" => ["not", "a", "string"]
      }

      vm = ResultRenderer.render(raw)
      assert vm.rows == []
      assert vm.issues == []
      assert vm.unauthorized_items == []
      assert vm.suggestions == []
      assert vm.photo_quality == %{score: nil, notes: nil}
      assert vm.extracted_products == []
      assert vm.executive_summary == "(no summary returned)"
    end

    test "tolerates non-map row entries without crashing" do
      raw = %{"rows" => ["bad-row-as-string", 42, nil, %{"name" => "Real row"}]}
      vm = ResultRenderer.render(raw)
      assert length(vm.rows) == 4
      assert Enum.at(vm.rows, 3).name == "Real row"
      # Bad entries get defaults
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
