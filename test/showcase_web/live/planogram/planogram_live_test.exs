defmodule ShowcaseWeb.Planogram.PlanogramLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  import Phoenix.LiveViewTest

  alias Showcase.Planogram.{Seed, MockPrompts}

  setup do
    Seed.seed()
    MockPrompts.register_all()
    :ok
  end

  describe "merchandiser view (default)" do
    test "renders the role switcher and Merchandiser headline", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/planogram")
      assert html =~ "Merchandiser"
      assert html =~ "Today"
      assert html =~ "Overdue"
    end

    test "lists 3 seeded tasks bucketed by due date", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      rendered = render(view)
      assert rendered =~ "Downtown Mart"
      assert rendered =~ "Westside Express"
      assert rendered =~ "Eastpark Grocery"
    end

    test "switches role to Manager via phx-click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      assert view |> element("button", "Manager") |> render_click() =~ "Author planograms"
    end

    test "Run analysis enqueues an Oban job", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      # Pick the first task's "Run analysis" button via its phx-value-task_id
      task = Showcase.Planogram.list_tasks() |> hd()

      view
      |> element("button[phx-click='run_analysis'][phx-value-task_id='#{task.id}']")
      |> render_click()

      assert_enqueued(worker: Showcase.Planogram.Worker)
    end
  end

  describe "QR handoff" do
    test "renders an SVG QR code for the active task", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      task = Showcase.Planogram.list_tasks() |> hd()

      view
      |> element("button[phx-click='toggle_qr'][phx-value-task_id='#{task.id}']")
      |> render_click()

      rendered = render(view)
      assert rendered =~ "<svg"
      assert rendered =~ "/planogram/mobile/"
    end
  end
end
