defmodule ShowcaseWeb.DashboardLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the dashboard at /", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Neurony AI Showcase"
    assert html =~ "OrderFlow"
  end

  test "live tile shows 'Live' badge and links to its path", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Live"
    assert html =~ ~s(href="/order-flow")
  end

  test "all 5 demo tiles are present on the dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "OrderFlow"
    assert html =~ "RecruitFlow"
    assert html =~ "Planogram Manager"
    assert html =~ "Invoice Approval"
    assert html =~ "Restaurant Compliance"
  end

  test "all 5 tile descriptions are present", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    # Sample one phrase from each — the full strings are too long for clean matches
    assert html =~ "unstructured customer messages"  # OrderFlow
    assert html =~ "5-state funnel"                   # RecruitFlow
    assert html =~ "Retail shelf compliance"          # Planogram
    assert html =~ "Three-way matching"               # Invoice
    assert html =~ "mise-en-place"                    # Restaurant Compliance
  end
end
