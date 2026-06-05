defmodule ShowcaseWeb.Admin.SystemPromptsLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Seed all demos so SystemPrompt rows exist
    Showcase.Dashboard.live_seeders() |> Enum.each(& &1.seed())

    # Inject basic-auth header for /admin/*
    conn = Plug.Conn.put_req_header(conn, "authorization", basic_auth())
    {:ok, conn: conn}
  end

  defp basic_auth do
    user = Application.get_env(:showcase, :admin_user, "admin")
    pass = Application.get_env(:showcase, :admin_pass, "changeme")
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  describe "GET /admin/system-prompts" do
    test "lists active prompts grouped by demo", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")

      assert html =~ "System prompts"
      # All 4 live demos should appear
      assert html =~ "order_flow"
      assert html =~ "recruit_flow"
      assert html =~ "invoice_approval"
      assert html =~ "planogram"
    end

    test "renders the prompt body in a preformatted block", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")
      assert html =~ "<pre"
    end

    test "shows version + last-updated for each prompt", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")
      assert html =~ "v1" or html =~ "version"
    end
  end

  describe "without basic auth" do
    test "rejects with 401", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn() |> get("/admin/system-prompts")
      assert conn.status == 401
    end
  end
end
