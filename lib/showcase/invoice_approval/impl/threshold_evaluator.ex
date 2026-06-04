defmodule Showcase.InvoiceApproval.Impl.ThresholdEvaluator do
  @moduledoc """
  Pure threshold-application logic. Separates business rules from the LLM:
  Claude produces raw `Discrepancy` rows; this module classifies each one
  as `:green | :amber | :red` and rolls them up to an outcome.

  Classification:
    * `:green` if `diff_value` ≤ threshold for the discrepancy's basis.
    * `:amber` if threshold < `diff_value` ≤ 2× threshold.
    * `:red` if `diff_value` > 2× threshold.
    * Out-of-contract / missing-in-invoice / other "categorical" discrepancies
      bypass thresholds and are always `:red`.

  Outcome:
    * Any `:red` row → `:reject`.
    * No `:red`, at least one `:amber` → `:needs_human`.
    * All `:green` → `:approve`.
  """

  alias Showcase.InvoiceApproval.Impl.Types.{ClassifiedDiscrepancy, Discrepancy, MatchingMatrixRow}

  @type thresholds :: %{price_pct: float(), qty_pct: float(), date_days: number()}
  @type outcome :: :approve | :reject | :needs_human

  @categorical_red [:sku_not_in_contract, :missing_in_invoice, :missing_in_delivery, :expired_contract]

  @doc "Pick the threshold for this discrepancy's field, or `nil` if categorical."
  @spec threshold_for(Discrepancy.t(), thresholds()) :: number() | nil
  def threshold_for(%Discrepancy{field: field, diff_basis: :pct}, thresholds)
      when field in [:unit_price, :total_price],
      do: thresholds.price_pct

  def threshold_for(%Discrepancy{field: :quantity, diff_basis: :pct}, thresholds),
    do: thresholds.qty_pct

  def threshold_for(%Discrepancy{field: field, diff_basis: :days}, thresholds)
      when field in [:date, :due_date, :delivery_date],
      do: thresholds.date_days

  def threshold_for(_, _), do: nil

  @spec classify_severity(Discrepancy.t(), thresholds()) :: ClassifiedDiscrepancy.severity()
  def classify_severity(%Discrepancy{field: field} = d, thresholds) do
    if field in @categorical_red do
      :red
    else
      case threshold_for(d, thresholds) do
        nil -> :red
        threshold ->
          cond do
            d.diff_value <= threshold -> :green
            d.diff_value <= 2 * threshold -> :amber
            true -> :red
          end
      end
    end
  end

  @doc """
  Apply thresholds to a raw matrix (list of row-shaped maps with raw Discrepancy
  structs in `:discrepancies`). Returns `%{outcome, classified_matrix, reasoning}`.
  """
  @spec evaluate(list(map()), thresholds()) ::
          %{outcome: outcome(), classified_matrix: list(MatchingMatrixRow.t()), reasoning: String.t()}
  def evaluate(raw_matrix, thresholds) when is_list(raw_matrix) do
    classified = Enum.map(raw_matrix, &classify_row(&1, thresholds))

    outcome = outcome_from(classified)
    reasoning = build_reasoning(outcome, classified)

    %{outcome: outcome, classified_matrix: classified, reasoning: reasoning}
  end

  defp classify_row(row, thresholds) do
    classified_discs =
      Enum.map(row.discrepancies, fn disc ->
        severity = classify_severity(disc, thresholds)
        %ClassifiedDiscrepancy{
          discrepancy: disc,
          severity: severity,
          note: build_disc_note(disc, severity, thresholds)
        }
      end)

    %MatchingMatrixRow{
      line_key: row.line_key,
      contract: row.contract,
      delivery: row.delivery,
      invoice: row.invoice,
      discrepancies: classified_discs
    }
  end

  @spec outcome_from(list(MatchingMatrixRow.t())) :: outcome()
  def outcome_from(classified_matrix) do
    severities =
      classified_matrix
      |> Enum.flat_map(& &1.discrepancies)
      |> Enum.map(& &1.severity)

    cond do
      :red in severities -> :reject
      :amber in severities -> :needs_human
      true -> :approve
    end
  end

  defp build_reasoning(:approve, _classified), do: "All lines match within configured tolerances."

  defp build_reasoning(:reject, classified) do
    worst =
      classified
      |> Enum.flat_map(fn row -> Enum.map(row.discrepancies, &{row.line_key, &1}) end)
      |> Enum.find(fn {_lk, cd} -> cd.severity == :red end)

    case worst do
      {line_key, cd} ->
        "Reject — line #{line_key} has #{cd.discrepancy.field} diff #{cd.discrepancy.diff_value} #{cd.discrepancy.diff_basis} beyond threshold. " <>
          (cd.note || "")

      nil ->
        "Reject."
    end
  end

  defp build_reasoning(:needs_human, classified) do
    amber_count =
      classified
      |> Enum.flat_map(& &1.discrepancies)
      |> Enum.count(&(&1.severity == :amber))

    "Needs human review — #{amber_count} discrepanc#{if amber_count == 1, do: "y", else: "ies"} within tolerance window."
  end

  defp build_disc_note(%Discrepancy{} = d, :green, _t),
    do: "Within tolerance (#{d.diff_value} #{d.diff_basis})"

  defp build_disc_note(%Discrepancy{} = d, :amber, _t),
    do: "Above tolerance — diff #{d.diff_value} #{d.diff_basis}"

  defp build_disc_note(%Discrepancy{} = d, :red, _t),
    do: "Significantly above tolerance — diff #{d.diff_value} #{d.diff_basis}"
end
