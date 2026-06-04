defmodule Showcase.OrderFlow.Impl.AliasPromotion do
  @moduledoc """
  Pure logic for deciding when a client-scoped product alias should be
  promoted to a global alias.

  Rule (per spec §4.1): a `normalized_text → product_id` mapping is eligible
  for global promotion once at least 2 distinct clients have written it AND
  the mean confidence across all entries is ≥ 0.7.
  """

  @min_distinct_clients 2
  @min_avg_confidence 0.7

  @type alias_row :: %{client_id: integer(), confidence: float()}

  @spec eligible_for_global?(list(alias_row())) :: boolean()
  def eligible_for_global?(entries) when is_list(entries) do
    distinct = entries |> Enum.map(& &1.client_id) |> Enum.uniq() |> length()

    if distinct < @min_distinct_clients do
      false
    else
      avg = entries |> Enum.map(& &1.confidence) |> mean()
      avg >= @min_avg_confidence
    end
  end

  defp mean([]), do: 0.0
  defp mean(xs) when is_list(xs), do: Enum.sum(xs) / length(xs)
end
