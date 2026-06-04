defmodule Showcase.OrderFlow.Impl.NormalizeTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.Normalize

  describe "normalize_text/1" do
    test "lowercases" do
      assert Normalize.normalize_text("HINGES") == "hinges"
    end

    test "trims surrounding whitespace" do
      assert Normalize.normalize_text("  widget   ") == "widget"
    end

    test "collapses internal whitespace" do
      assert Normalize.normalize_text("door     lock") == "door lock"
    end

    test "strips common punctuation" do
      assert Normalize.normalize_text("4mm gaskets!") == "4mm gaskets"
      assert Normalize.normalize_text("widget, large") == "widget large"
      assert Normalize.normalize_text("hinge (heavy duty)") == "hinge heavy duty"
    end

    test "preserves digits and alphanumeric SKU-like tokens" do
      assert Normalize.normalize_text("SKU-00142") == "sku-00142"
      assert Normalize.normalize_text("M8x40") == "m8x40"
    end

    test "empty string returns empty string" do
      assert Normalize.normalize_text("") == ""
    end

    test "nil raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Normalize.normalize_text(nil) end
    end
  end
end
