defmodule Showcase.OrderFlow.Impl.ConfidenceDecayTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.ConfidenceDecay

  @now ~U[2026-06-04 12:00:00.000000Z]

  describe "decay/3" do
    test "recent use (< 6 months) returns raw confidence unchanged" do
      one_month_ago = DateTime.add(@now, -30, :day)
      assert ConfidenceDecay.decay(0.85, one_month_ago, @now) == 0.85
    end

    test "5 months and 29 days returns raw confidence (boundary inside fresh window)" do
      almost_six = DateTime.add(@now, -180 + 1, :day)
      assert ConfidenceDecay.decay(0.85, almost_six, @now) == 0.85
    end

    test "exactly 6 months starts decaying" do
      six_months = DateTime.add(@now, -180, :day)
      decayed = ConfidenceDecay.decay(0.85, six_months, @now)
      assert decayed < 0.85
      assert decayed > 0.1
    end

    test "9 months decays roughly halfway" do
      nine_months = DateTime.add(@now, -270, :day)
      decayed = ConfidenceDecay.decay(0.85, nine_months, @now)
      midpoint = (0.85 + 0.1) / 2
      assert_in_delta decayed, midpoint, 0.02
    end

    test "12 months returns :expired" do
      twelve_months = DateTime.add(@now, -365, :day)
      assert ConfidenceDecay.decay(0.85, twelve_months, @now) == :expired
    end

    test "more than 12 months returns :expired" do
      ancient = DateTime.add(@now, -730, :day)
      assert ConfidenceDecay.decay(0.5, ancient, @now) == :expired
    end

    test "raw_confidence at floor returns floor (until expiry)" do
      one_month_ago = DateTime.add(@now, -30, :day)
      assert ConfidenceDecay.decay(0.1, one_month_ago, @now) == 0.1
    end
  end
end
