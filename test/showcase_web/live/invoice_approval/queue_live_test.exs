defmodule ShowcaseWeb.InvoiceApproval.QueueLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.InvoiceApproval.Seed

  setup do
    Seed.seed()
    :ok
  end

  test "renders the queue at /invoice-approval", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invoice-approval")

    assert html =~ "Invoice Approval"
    assert html =~ "Bundle"
  end

  test "shows seeded scenarios", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invoice-approval")

    assert html =~ "clean_match"
    assert html =~ "price_drift"
    assert html =~ "qty_mismatch"
    assert html =~ "out_of_contract"
  end
end
