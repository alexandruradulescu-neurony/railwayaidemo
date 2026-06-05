defmodule ShowcaseWeb.Admin.AuditLogLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Write a couple of synthetic audit entries
    Showcase.Common.AuditLog
    |> Ash.Changeset.for_create(:write, %{
      demo: "recruit_flow",
      entity_type: "application",
      entity_id: "1",
      event: "state_change",
      payload: %{from: "PENDING", to: "QUALIFIED"},
      actor: "alex@neurony.ro"
    })
    |> Ash.create!()

    Showcase.Common.AuditLog
    |> Ash.Changeset.for_create(:write, %{
      demo: "invoice_approval",
      entity_type: "bundle",
      entity_id: "42",
      event: "verdict_override",
      payload: %{from: "needs_human", to: "approve", reason: "AE override"},
      actor: "alex@neurony.ro"
    })
    |> Ash.create!()

    conn = Plug.Conn.put_req_header(conn, "authorization", basic_auth())
    {:ok, conn: conn}
  end

  defp basic_auth do
    user = Application.get_env(:showcase, :admin_user, "admin")
    pass = Application.get_env(:showcase, :admin_pass, "changeme")
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  describe "GET /admin/audit-log" do
    test "lists entries newest-first", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/audit-log")

      assert html =~ "Audit log"
      assert html =~ "recruit_flow"
      assert html =~ "invoice_approval"
      assert html =~ "state_change"
      assert html =~ "verdict_override"
      assert html =~ "alex@neurony.ro"
    end

    test "filters by demo when ?demo=<x>", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/audit-log?demo=recruit_flow")
      assert html =~ "state_change"
      refute html =~ "verdict_override"
    end

    test "renders empty state cleanly", %{conn: _conn} do
      # Wipe + new request
      Showcase.Common.AuditLog |> Ash.read!() |> Enum.each(&Ash.destroy!/1)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", basic_auth())

      {:ok, _view, html} = live(conn, "/admin/audit-log")
      assert html =~ "No audit entries"
    end
  end

  describe "without basic auth" do
    test "rejects with 401", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn() |> get("/admin/audit-log")
      assert conn.status == 401
    end
  end
end
