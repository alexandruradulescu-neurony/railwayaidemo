defmodule Showcase.InvoiceApproval.Impl.TypesTest do
  use ExUnit.Case, async: true

  alias Showcase.InvoiceApproval.Impl.Types
  alias Showcase.InvoiceApproval.Impl.Types.{Discrepancy, ClassifiedDiscrepancy, MatchingMatrixRow}

  test "Discrepancy struct enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(Discrepancy, %{})
    end
  end

  test "Discrepancy with required keys constructs cleanly" do
    d = %Discrepancy{
      field: :unit_price,
      contract_value: 10.0,
      delivery_value: 10.0,
      invoice_value: 10.5,
      diff_value: 5.0,
      diff_basis: :pct
    }

    assert d.field == :unit_price
    assert d.diff_basis == :pct
  end

  test "ClassifiedDiscrepancy wraps a Discrepancy with severity + note" do
    d = %Discrepancy{
      field: :quantity,
      contract_value: 100,
      delivery_value: 100,
      invoice_value: 95,
      diff_value: 5.0,
      diff_basis: :pct
    }

    classified = %ClassifiedDiscrepancy{discrepancy: d, severity: :amber, note: "5% qty drift"}

    assert classified.severity == :amber
    assert classified.discrepancy.field == :quantity
  end

  test "MatchingMatrixRow holds line_key + per-doc cells + classified discrepancies" do
    row = %MatchingMatrixRow{
      line_key: "WGT-001",
      contract: %{qty: 100, unit_price: 10.0},
      delivery: %{qty: 100, unit_price: 10.0},
      invoice: %{qty: 100, unit_price: 10.5},
      discrepancies: []
    }

    assert row.line_key == "WGT-001"
    assert row.contract.qty == 100
  end

  test "row_severity/1 returns :green when no discrepancies" do
    assert Types.row_severity(%MatchingMatrixRow{
             line_key: "x",
             contract: %{},
             delivery: %{},
             invoice: %{},
             discrepancies: []
           }) == :green
  end

  test "row_severity/1 returns the worst severity across discrepancies" do
    row = %MatchingMatrixRow{
      line_key: "x",
      contract: %{},
      delivery: %{},
      invoice: %{},
      discrepancies: [
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :a, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :green, note: ""},
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :b, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :amber, note: ""},
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :c, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :red, note: ""}
      ]
    }

    assert Types.row_severity(row) == :red
  end
end
