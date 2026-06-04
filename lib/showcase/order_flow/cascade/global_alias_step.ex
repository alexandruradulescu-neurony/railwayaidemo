defmodule Showcase.OrderFlow.Cascade.GlobalAliasStep do
  @moduledoc """
  Fourth step in the OrderFlow cascade.

  Queries the **global** alias pool (`client_id IS NULL`). Same decay rules
  as `ClientAliasStep`. Runs regardless of the request's client_id.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.{ConfidenceDecay, Normalize}
  alias Showcase.OrderFlow.Schemas.ProductAlias

  @impl true
  def name, do: :global_alias

  @impl true
  def try_match(input, %{repo: repo, now: now}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from a in ProductAlias,
        where: is_nil(a.client_id) and a.normalized_text == ^normalized,
        order_by: [desc: a.last_used_at],
        preload: [:product]

    case repo.all(query) do
      [] ->
        :no_match

      aliases ->
        aliases
        |> Enum.map(&{&1, ConfidenceDecay.decay(&1.confidence, &1.last_used_at, now)})
        |> Enum.reject(fn {_a, c} -> c == :expired end)
        |> case do
          [] -> :no_match
          [{alias_row, decayed_confidence} | _] -> {:match, alias_row.product, decayed_confidence}
        end
    end
  end
end
