defmodule Showcase.OrderFlow.Cascade.ExactStep do
  @moduledoc """
  First step in the OrderFlow product-matching cascade.

  Looks up `Product` by `normalized_name == Normalize.normalize_text(input)`.
  Returns a 1.0 confidence match on hit, `:no_match` otherwise.
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

    case repo.one(from p in Product, where: p.normalized_name == ^normalized) do
      nil -> :no_match
      %Product{} = product -> {:match, product, 1.0}
    end
  end
end
