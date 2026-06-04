defmodule Showcase.InvoiceApproval.Impl.Types do
  @moduledoc """
  Structs that flow through the Invoice Approval pipeline:

    * `Discrepancy` — raw output from Claude, before threshold classification.
    * `ClassifiedDiscrepancy` — same data + a `:severity` (`:green | :amber | :red`)
      assigned by `ThresholdEvaluator`.
    * `MatchingMatrixRow` — one row across all three documents, with the line's
      classified discrepancies.

  Plus a `row_severity/1` helper that returns the worst severity of any
  classified discrepancy on a row (or `:green` if there are none).
  """

  defmodule Discrepancy do
    @enforce_keys [:field, :contract_value, :delivery_value, :invoice_value, :diff_value, :diff_basis]
    defstruct [:field, :contract_value, :delivery_value, :invoice_value, :diff_value, :diff_basis]

    @type t :: %__MODULE__{
            field: atom(),
            contract_value: any(),
            delivery_value: any(),
            invoice_value: any(),
            diff_value: float(),
            diff_basis: :pct | :absolute | :days
          }
  end

  defmodule ClassifiedDiscrepancy do
    @enforce_keys [:discrepancy, :severity, :note]
    defstruct [:discrepancy, :severity, :note]

    @type severity :: :green | :amber | :red
    @type t :: %__MODULE__{discrepancy: Discrepancy.t(), severity: severity(), note: String.t()}
  end

  defmodule MatchingMatrixRow do
    @enforce_keys [:line_key, :contract, :delivery, :invoice, :discrepancies]
    defstruct [:line_key, :contract, :delivery, :invoice, :discrepancies]

    @type t :: %__MODULE__{
            line_key: String.t(),
            contract: map(),
            delivery: map(),
            invoice: map(),
            discrepancies: list(ClassifiedDiscrepancy.t())
          }
  end

  @doc """
  Returns the worst severity across the row's classified discrepancies.
  `:green` when there are no discrepancies.
  """
  @spec row_severity(MatchingMatrixRow.t()) :: ClassifiedDiscrepancy.severity()
  def row_severity(%MatchingMatrixRow{discrepancies: []}), do: :green

  def row_severity(%MatchingMatrixRow{discrepancies: discs}) do
    severities = Enum.map(discs, & &1.severity)

    cond do
      :red in severities -> :red
      :amber in severities -> :amber
      true -> :green
    end
  end
end
