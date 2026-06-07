defmodule ShowcaseWeb.Admin.ResetLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Schemas.SyntheticMessage
  alias Showcase.Repo

  setup do
    # admin_basic_auth_test.exs (async: true) globally mutates these — pin them here
    # so this suite runs deterministically regardless of order.
    Application.put_env(:showcase, :admin_user, "admin")
    Application.put_env(:showcase, :admin_pass, "changeme")
    :ok
  end

  defp authed_conn(conn),
    do: Plug.Conn.put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:changeme"))

  test "renders without crashing", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    assert html =~ "Reset"
    assert html =~ "OrderFlow"
  end

  test "shows a button per live demo", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    # OrderFlow is the only live demo right now — should appear once as a button
    assert html =~ "Reset OrderFlow"
  end

  test "shows a global 'Reset all demos' button", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    assert html =~ "Reset all demos"
  end

  test "global reset triggers Common.Reset.run with all live seeders", %{conn: conn} do
    # Seed first so there's data to wipe
    Showcase.OrderFlow.Seed.seed()
    Repo.insert!(%SyntheticMessage{body: "manual", kind: "email", scenario: "test_only", client_hint: nil})

    assert Repo.aggregate(SyntheticMessage, :count) >= 4

    {:ok, view, _html} = live(authed_conn(conn), "/admin/reset")
    render_click(view, "reset_all", %{})

    # After reset: synthetic_messages count should be back to seed baseline (the 3 demo scenarios)
    count = Repo.aggregate(SyntheticMessage, :count)
    assert count == 3
  end

  test "per-demo reset triggers Reset.run with only that seeder", %{conn: conn} do
    Showcase.OrderFlow.Seed.seed()
    Repo.insert!(%SyntheticMessage{body: "manual", kind: "email", scenario: "test_only", client_hint: nil})

    {:ok, view, _html} = live(authed_conn(conn), "/admin/reset")
    render_click(view, "reset_demo", %{"id" => "order_flow"})

    count = Repo.aggregate(SyntheticMessage, :count)
    assert count == 3
  end
end
