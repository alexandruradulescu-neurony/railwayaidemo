defmodule Showcase.OrderFlow.Cascade.ClientAliasStep do
  @moduledoc """
  Third step in the OrderFlow cascade.

  Looks up `ProductAlias` rows scoped to the current `client_id` matching the
  normalized input. Applies time-based confidence decay; filters out expired
  entries. Returns the freshest match (highest `last_used_at`) with its
  decayed confidence.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.{ConfidenceDecay, Normalize}
  alias Showcase.OrderFlow.Schemas.ProductAlias

  @impl true
  def name, do: :client_alias

  @impl true
  def try_match(_input, %{client_id: nil}), do: :no_match

  @impl true
  def try_match(input, %{repo: repo, now: now, client_id: client_id}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from a in ProductAlias,
        where: a.client_id == ^client_id and a.normalized_text == ^normalized,
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
