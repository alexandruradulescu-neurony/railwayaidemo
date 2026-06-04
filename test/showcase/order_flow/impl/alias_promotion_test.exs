defmodule Showcase.OrderFlow.Impl.AliasPromotionTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.AliasPromotion

  describe "eligible_for_global?/1" do
    test "false when zero matches" do
      refute AliasPromotion.eligible_for_global?([])
    end

    test "false when only one client uses the alias" do
      refute AliasPromotion.eligible_for_global?([%{client_id: 1, confidence: 0.95}])
    end

    test "false when 2+ clients but average confidence < 0.7" do
      refute AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.6},
        %{client_id: 2, confidence: 0.55}
      ])
    end

    test "true when 2 distinct clients and avg confidence >= 0.7" do
      assert AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.85},
        %{client_id: 2, confidence: 0.75}
      ])
    end

    test "false when 2 entries are from same client" do
      refute AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.9},
        %{client_id: 1, confidence: 0.9}
      ])
    end

    test "true when 3+ clients drag avg confidence up despite one weak entry" do
      assert AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.9},
        %{client_id: 2, confidence: 0.9},
        %{client_id: 3, confidence: 0.4}
      ])
    end
  end
end
