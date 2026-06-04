defmodule Showcase.OrderFlow.Worker do
  @moduledoc """
  Oban worker that processes a SyntheticMessage through the OrderFlow pipeline.

  Enqueued by `Showcase.OrderFlow.enqueue_random/0` (the public context, T14).
  Runs on the `:order_flow` queue configured in `config/config.exs` since Phase 0.
  """

  use Oban.Worker, queue: :order_flow, max_attempts: 3

  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.SyntheticMessage
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    case Repo.get(SyntheticMessage, message_id) do
      nil ->
        {:error, :not_found}

      %SyntheticMessage{} = msg ->
        case Pipeline.process_message(msg, %{now: DateTime.utc_now()}) do
          {:ok, _order} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
