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
end
