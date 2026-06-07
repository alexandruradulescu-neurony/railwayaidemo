defmodule Showcase.OrderFlow.PipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.{Client, Product, SyntheticMessage}
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widgets", normalized_name: "widgets"})
      |> Repo.insert()

    {:ok, gadget} =
      %Product{}
      |> Product.changeset(%{sku: "GDG-001", name: "Gadgets", normalized_name: "gadgets"})
      |> Repo.insert()

    {:ok, msg} =
      %SyntheticMessage{}
      |> SyntheticMessage.changeset(%{
        body: "200 widgets and 50 gadgets",
        kind: "email",
        scenario: "widgets_gadgets",
        client_hint: "Acme Inc"
      })
      |> Repo.insert()

    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widgets", "quantity": 200}, {"description": "gadgets", "quantity": 50}]})
    )

    {:ok, %{client: client, widget: widget, gadget: gadget, message: msg}}
  end

  defp ctx, do: %{now: DateTime.utc_now()}

  test "creates an Order with matched lines for a clean happy path",
       %{message: msg, client: client, widget: widget, gadget: gadget} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "order_flow:processing:#{msg.id}")

    {:ok, order} = Pipeline.process_message(msg, ctx())

    assert order.client_id == client.id
    assert order.status == "pending_review"

    lines = Repo.preload(order, :lines).lines |> Enum.sort_by(& &1.quantity, :desc)
    assert length(lines) == 2

    [widgets, gadgets] = lines
    assert widgets.product_id == widget.id
    assert widgets.quantity == 200
    assert widgets.match_step == "exact"

    assert gadgets.product_id == gadget.id
    assert gadgets.quantity == 50
    assert gadgets.match_step == "exact"

    # PubSub broadcasts received
    assert_received {:order_flow, :extracted, _}
    assert_received {:order_flow, :client_identified, _}
    # one :line_matched per line
    assert_received {:order_flow, :line_matched, %{step: :exact}}
    assert_received {:order_flow, :line_matched, %{step: :exact}}
    assert_received {:order_flow, :order_created, %{order_id: _}}
  end

  test "creates a needs_client order when client_hint can't be resolved",
       %{message: msg} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "order_flow:processing:#{msg.id}")

    Mock.reset()
    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Unknown Co", "lines": [{"description": "widget", "quantity": 1}]})
    )

    # Pipeline no longer stops on client resolution failure — it creates the
    # order with client_id=nil and status="needs_client" so the operator can
    # pick a client by hand on the order detail page.
    {:ok, order} = Pipeline.process_message(msg, ctx())

    assert order.client_id == nil
    assert order.status == "needs_client"
    assert_received {:order_flow, :client_unresolved, _}
    assert_received {:order_flow, :order_created, %{order_id: _}}
  end

  test "creates order line with nil product_id when no cascade step matches",
       %{message: msg} do
    Mock.reset()
    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "mystery item", "quantity": 1}]})
    )

    {:ok, order} = Pipeline.process_message(msg, ctx())
    lines = Repo.preload(order, :lines).lines

    assert length(lines) == 1
    assert hd(lines).product_id == nil
    assert hd(lines).match_step == nil
  end
end
