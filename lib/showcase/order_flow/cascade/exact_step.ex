defmodule Showcase.OrderFlow.Cascade.ExactStep do
  @moduledoc """
  First step in the OrderFlow product-matching cascade.

  Looks up `Product` by:

    1. `normalized_name == Normalize.normalize_text(input)` — descriptive
       exact text match.
    2. `lower(sku) == Normalize.normalize_text(input)` — direct SKU match
       (so an extracted SKU string like `"K1001-07-n03"` resolves to the
       product with that SKU regardless of how the descriptive
       `normalized_name` is shaped).

  Either path returns a 1.0 confidence match.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.Normalize
  alias Showcase.OrderFlow.Schemas.Product

  @impl true
  def name, do: :exact

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from p in Product,
        where:
          p.normalized_name == ^normalized or
            fragment("lower(?)", p.sku) == ^normalized,
        limit: 1

    case repo.one(query) do
      nil -> :no_match
      %Product{} = product -> {:match, product, 1.0}
    end
  end
end
