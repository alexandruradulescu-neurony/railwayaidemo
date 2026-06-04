defmodule Showcase.OrderFlow.Cascade.FuzzyTrigramStep do
  @moduledoc """
  Second step in the OrderFlow cascade.

  Uses Postgres `pg_trgm` similarity (extension enabled in Phase 0) to find
  the closest `Product.normalized_name` to the input. Returns the highest
  similarity if it meets the threshold.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.Normalize
  alias Showcase.OrderFlow.Schemas.Product

  @similarity_threshold 0.5

  @impl true
  def name, do: :fuzzy_trigram

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from p in Product,
        select: {p, fragment("similarity(?, ?)", p.normalized_name, ^normalized)},
        order_by: [desc: fragment("similarity(?, ?)", p.normalized_name, ^normalized)],
        limit: 1

    case repo.one(query) do
      nil ->
        :no_match

      {%Product{} = product, score} when score >= @similarity_threshold ->
        {:match, product, score}

      _ ->
        :no_match
    end
  end
end
