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
    assert html =~ "Receive an invoice"
  end

  test "shows seeded scenarios", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invoice-approval")

    # Seeded bundle clients (Meesenburg Romanian feronerie demo set)
    assert html =~ "Meesenburg Romania"
    assert html =~ "Alexandru Erdei"
    assert html =~ "Dragos Manolache"
  end
end
