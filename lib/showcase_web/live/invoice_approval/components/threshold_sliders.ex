defmodule ShowcaseWeb.InvoiceApproval.Components.ThresholdSliders do
  @moduledoc """
  Three range sliders that drive `phx-change="update_thresholds"`.
  The parent LiveView re-evaluates the matrix on each change.
  """

  use Phoenix.Component

  attr :thresholds, :map, required: true,
    doc: ~s(map with "price_pct", "qty_pct", "date_days" keys)

  def threshold_sliders(assigns) do
    ~H"""
    <form phx-change="update_thresholds" class="space-y-4">
      <div>
        <label class="block text-xs uppercase tracking-wide text-ink/60">
          Price tolerance: {(@thresholds["price_pct"] || 5.0)}%
        </label>
        <input
          type="range"
          name="price_pct"
          min="0"
          max="20"
          step="0.5"
          value={@thresholds["price_pct"] || 5.0}
          class="w-full"
        />
      </div>

      <div>
        <label class="block text-xs uppercase tracking-wide text-ink/60">
          Quantity tolerance: {(@thresholds["qty_pct"] || 2.0)}%
        </label>
        <input
          type="range"
          name="qty_pct"
          min="0"
          max="20"
          step="0.5"
          value={@thresholds["qty_pct"] || 2.0}
          class="w-full"
        />
      </div>

      <div>
        <label class="block text-xs uppercase tracking-wide text-ink/60">
          Date tolerance: {(@thresholds["date_days"] || 3)} days
        </label>
        <input
          type="range"
          name="date_days"
          min="0"
          max="30"
          step="1"
          value={@thresholds["date_days"] || 3}
          class="w-full"
        />
      </div>
    </form>
    """
  end
end
