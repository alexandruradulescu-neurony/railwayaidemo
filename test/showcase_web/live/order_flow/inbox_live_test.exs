defmodule ShowcaseWeb.OrderFlow.InboxLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Seed

  setup do
    Seed.seed()
    :ok
  end

  test "mounts and renders the inbox", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/order-flow")

    assert html =~ "OrderFlow"
    assert html =~ "Generate order"
  end

  test "shows seeded messages in the inbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    # at least one seeded scenario name visible
    assert render(view) =~ "Acme Inc"
  end

  test "generate_order enqueues a worker and shows progress", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    render_click(view, "generate_order", %{})

    # Pipeline runs asynchronously via Oban — for the test we have testing :manual,
    # so manually drain the queue.
    Oban.drain_queue(queue: :order_flow)

    # Render after drain — at minimum, the "Processing:" indicator went up
    html = render(view)
    assert html =~ "Processing:"
  end
end
