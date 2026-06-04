defmodule Showcase.InvoiceApproval.Impl.ThresholdEvaluatorTest do
  use ExUnit.Case, async: true

  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Impl.Types.Discrepancy

  @thresholds %{price_pct: 5.0, qty_pct: 2.0, date_days: 3}

  defp row(line_key, discs) do
    %{
      line_key: line_key,
      contract: %{},
      delivery: %{},
      invoice: %{},
      discrepancies: discs
    }
  end

  defp d(field, diff, basis) do
    %Discrepancy{
      field: field,
      contract_value: 0,
      delivery_value: 0,
      invoice_value: 0,
      diff_value: diff,
      diff_basis: basis
    }
  end

  describe "classify_severity/2" do
    test "price discrepancy within threshold → :green" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 3.0, :pct), @thresholds) == :green
    end

    test "price discrepancy at threshold → :green" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 5.0, :pct), @thresholds) == :green
    end

    test "price discrepancy between threshold and 2x → :amber" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 7.5, :pct), @thresholds) == :amber
    end

    test "price discrepancy at 2x threshold → :amber" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 10.0, :pct), @thresholds) == :amber
    end

    test "price discrepancy beyond 2x → :red" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 15.0, :pct), @thresholds) == :red
    end

    test "qty discrepancy uses qty_pct threshold" do
      assert ThresholdEvaluator.classify_severity(d(:quantity, 1.0, :pct), @thresholds) == :green
      assert ThresholdEvaluator.classify_severity(d(:quantity, 3.0, :pct), @thresholds) == :amber
      assert ThresholdEvaluator.classify_severity(d(:quantity, 8.0, :pct), @thresholds) == :red
    end

    test "date discrepancy uses date_days threshold" do
      assert ThresholdEvaluator.classify_severity(d(:due_date, 2.0, :days), @thresholds) == :green
      assert ThresholdEvaluator.classify_severity(d(:due_date, 5.0, :days), @thresholds) == :amber
      assert ThresholdEvaluator.classify_severity(d(:due_date, 10.0, :days), @thresholds) == :red
    end

    test "out-of-contract discrepancy → :red regardless of threshold" do
      assert ThresholdEvaluator.classify_severity(d(:sku_not_in_contract, 0.0, :absolute), @thresholds) == :red
    end

    test "missing-in-invoice discrepancy → :red" do
      assert ThresholdEvaluator.classify_severity(d(:missing_in_invoice, 0.0, :absolute), @thresholds) == :red
    end
  end

  describe "evaluate/2" do
    test "all-green matrix → :approve" do
      raw_matrix = [
        row("A", [d(:unit_price, 1.0, :pct)]),
        row("B", [d(:quantity, 0.5, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :approve
      assert is_binary(result.reasoning)

      assert Enum.all?(result.classified_matrix, fn row ->
        Enum.all?(row.discrepancies, &(&1.severity == :green))
      end)
    end

    test "any-red matrix → :reject with reasoning citing the worst" do
      raw_matrix = [
        row("A", [d(:unit_price, 20.0, :pct)]),
        row("B", [d(:quantity, 0.5, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :reject
      assert result.reasoning =~ "A"
      assert result.reasoning =~ "unit_price"
    end

    test "amber-only matrix → :needs_human" do
      raw_matrix = [
        row("A", [d(:unit_price, 7.5, :pct)]),
        row("B", [d(:quantity, 3.0, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :needs_human
    end

    test "empty matrix → :approve" do
      assert ThresholdEvaluator.evaluate([], @thresholds).outcome == :approve
    end

    test "row with no discrepancies → contributes :green" do
      raw_matrix = [row("A", []), row("B", [d(:unit_price, 3.0, :pct)])]
      assert ThresholdEvaluator.evaluate(raw_matrix, @thresholds).outcome == :approve
    end
  end
end
