defmodule Showcase.OrderFlow.Pipeline do
  @moduledoc """
  Boundary that orchestrates the OrderFlow pipeline.

  Stages (each broadcasts PubSub on `order_flow:processing:<message_id>`):
    1. :extracted          — Claude returned {client_hint, lines}
    2. :client_identified  — client_hint resolved to a Client row
    3. :line_matched (×N)  — per line, one of the cascade steps matched (or all failed)
    4. :order_created      — Order + OrderLines inserted

  Returns `{:ok, %Order{}}` on success, `{:error, reason}` otherwise.
  """

  alias Ecto.Multi
  alias Showcase.Common.CascadeMatcher
  alias Showcase.OrderFlow.{ClientResolver, Extraction}
  alias Showcase.OrderFlow.Cascade.{
    ClaudeFallbackStep,
    ClientAliasStep,
    ExactStep,
    FuzzyTrigramStep,
    GlobalAliasStep
  }
  alias Showcase.OrderFlow.Schemas.{Order, OrderLine, SyntheticMessage}
  alias Showcase.Repo

  @cascade_steps [
    ExactStep,
    FuzzyTrigramStep,
    ClientAliasStep,
    GlobalAliasStep,
    ClaudeFallbackStep
  ]

  @spec process_message(SyntheticMessage.t(), %{now: DateTime.t()}) ::
          {:ok, Order.t()} | {:error, term()}
  def process_message(%SyntheticMessage{} = msg, %{now: now}) do
    topic = "order_flow:processing:#{msg.id}"

    with {:ok, extracted} <- Extraction.extract(msg.body, scenario: msg.scenario),
         # Fall back to the synthetic message's seeded client_hint when Claude
         # can't infer one from the body (common for short / context-light
         # messages like "200 hinges and 50 locks — same as last month").
         effective_hint = extracted.client_hint || msg.client_hint,
         _ =
           broadcast(topic, :extracted, %{
             client_hint: effective_hint,
             line_count: length(extracted.lines)
           }),
         {:ok, client} <- resolve_client(effective_hint, topic) do
      matched_lines =
        Enum.map(extracted.lines, fn line ->
          context = %{repo: Repo, now: now, client_id: client.id}
          outcome = CascadeMatcher.run(@cascade_steps, line.description, context)

          attrs = %{
            raw_description: line.description,
            quantity: line.quantity,
            product_id: if(outcome.matched, do: outcome.value.id),
            confidence: outcome.confidence,
            match_step: if(outcome.step, do: to_string(outcome.step))
          }

          broadcast(topic, :line_matched, %{
            description: line.description,
            step: outcome.step,
            confidence: outcome.confidence,
            matched: outcome.matched
          })

          attrs
        end)

      multi =
        Multi.new()
        |> Multi.insert(
          :order,
          Order.changeset(%Order{}, %{
            client_id: client.id,
            status: "pending_review",
            synthetic_message_id: msg.id
          })
        )
        |> Multi.run(:lines, fn _repo, %{order: order} ->
          insert_lines(order, matched_lines)
        end)

      case Repo.transaction(multi) do
        {:ok, %{order: order}} ->
          broadcast(topic, :order_created, %{order_id: order.id})
          {:ok, order}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    else
      {:needs_human, reason} -> {:error, {:client_unresolved, reason}}
      {:error, _} = err -> err
    end
  end

  defp resolve_client(hint, topic) do
    case ClientResolver.resolve(hint, Repo) do
      {:ok, client} ->
        broadcast(topic, :client_identified, %{client_id: client.id, name: client.name})
        {:ok, client}

      {:needs_human, reason} = err ->
        broadcast(topic, :client_unresolved, %{reason: reason})
        err
    end
  end

  defp insert_lines(order, line_attrs) do
    results =
      Enum.map(line_attrs, fn attrs ->
        %OrderLine{}
        |> OrderLine.changeset(Map.put(attrs, :order_id, order.id))
        |> Repo.insert()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, line} -> line end)}
      {:error, _} = err -> err
    end
  end

  defp broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, topic, {:order_flow, event, payload})
  end
end
