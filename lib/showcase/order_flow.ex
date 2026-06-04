defmodule Showcase.OrderFlow do
  @moduledoc """
  Public context for the OrderFlow demo.

  Used by LiveViews to enqueue work, list inbox messages, find orders.
  Used by tests to bulk-register mock Anthropic responses.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.{Order, SyntheticMessage}
  alias Showcase.OrderFlow.Worker
  alias Showcase.Repo

  @doc """
  Enqueue a random unprocessed synthetic message. Returns the job + message
  so the caller can subscribe to PubSub by message_id.
  """
  @spec enqueue_random() ::
          {:ok, Oban.Job.t(), SyntheticMessage.t()} | {:error, :no_messages}
  def enqueue_random do
    case unprocessed_messages() do
      [] -> {:error, :no_messages}
      msgs ->
        msg = Enum.random(msgs)
        {:ok, job} = Worker.new(%{message_id: msg.id}) |> Oban.insert()
        {:ok, job, msg}
    end
  end

  defp unprocessed_messages do
    subquery =
      from o in Order,
        where: not is_nil(o.synthetic_message_id),
        select: o.synthetic_message_id

    from(m in SyntheticMessage,
      where: m.id not in subquery(subquery)
    )
    |> Repo.all()
  end

  @doc "All seeded synthetic messages."
  def list_messages, do: Repo.all(from m in SyntheticMessage, order_by: [asc: m.id])

  @doc "All orders, most recent first."
  def list_orders do
    from(o in Order, order_by: [desc: o.inserted_at], preload: [:client, lines: :product])
    |> Repo.all()
  end

  @doc "Fetch an order with its lines + client."
  def find_order(id) do
    Repo.get(Order, id) |> Repo.preload([:client, lines: :product])
  end

  @doc """
  Register mock responses for every scenario in `MockPrompts.scenarios/0`.
  Call from test setup (only the Mock impl is active in test env).
  """
  def register_mock_responses do
    Enum.each(MockPrompts.scenarios(), fn s ->
      Mock.register("order_flow:extract:v1",
        scenario: s.name,
        text: s.extract_response
      )

      Enum.each(s.fallback_responses, fn fr ->
        Mock.register("order_flow:claude_fallback:v1",
          scenario: fr.scenario,
          text: fr.text
        )
      end)
    end)
  end
end
