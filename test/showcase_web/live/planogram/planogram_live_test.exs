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
    end

    test "lists seeded tasks bucketed by due date", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      rendered = render(view)
      # 3 pharmacy + 2 juices from prod seed
      assert rendered =~ "Farmacia Tei Centru"
      assert rendered =~ "Sensiblu Băneasa"
      assert rendered =~ "Catena Plaza"
      assert rendered =~ "Hypermarket Băneasa"
      assert rendered =~ "Mega Image Centru"
    end

    test "switches role to Manager via phx-click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      assert view |> element("button", "Manager") |> render_click() =~ "Author planograms"
    end

    test "Run analysis enqueues an Oban job", %{conn: conn} do
      # The "Run analysis" button only renders when the task has a
      # `photo_path` (otherwise the worker would fail with :no_photo_attached
      # and leave the operator stuck). Set one on the first task before
      # mounting the LV so the button appears.
      task =
        Showcase.Planogram.list_tasks()
        |> hd()
        |> Showcase.Planogram.VerificationTask.changeset(%{
          photo_path: "/uploads/planogram/test-shelf.png"
        })
        |> Showcase.Repo.update!()

      {:ok, view, _html} = live(conn, "/planogram")

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

  describe "manager view" do
    test "lists existing planograms + create-task form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Manager") |> render_click()
      rendered = render(view)
      assert rendered =~ "Pharmacy OTC end-cap"
      assert rendered =~ "Create task"
      assert rendered =~ "Add planogram"
    end

    test "create_planogram inserts a new Planogram with uploaded reference", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Manager") |> render_click()

      before_count = Showcase.Repo.aggregate(Showcase.Planogram.Planogram, :count)

      png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>

      photo =
        file_input(view, "form[phx-submit='create_planogram']", :reference, [
          %{
            last_modified: 1_700_000_000_000,
            name: "ref.png",
            content: png_bytes,
            type: "image/png"
          }
        ])

      assert render_upload(photo, "ref.png") =~ "ref.png"

      view
      |> form("form[phx-submit='create_planogram']",
        %{
          "planogram" => %{
            "name" => "Brand new shelf #{System.unique_integer([:positive])}",
            "description" => "Test planogram via upload"
          }
        }
      )
      |> render_submit()

      after_count = Showcase.Repo.aggregate(Showcase.Planogram.Planogram, :count)
      assert after_count == before_count + 1
    end

    test "create_task inserts a new VerificationTask", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Manager") |> render_click()

      before_count = Showcase.Repo.aggregate(Showcase.Planogram.VerificationTask, :count)

      view
      |> form("form[phx-submit='create_task']",
        %{
          "task" => %{
            "store_name" => "New Test Store",
            "due_date" => Date.to_iso8601(Date.utc_today()),
            "planogram_id" => first_planogram_id()
          }
        })
      |> render_submit()

      after_count = Showcase.Repo.aggregate(Showcase.Planogram.VerificationTask, :count)
      assert after_count == before_count + 1
    end

    defp first_planogram_id do
      [pg | _] = Showcase.Repo.all(Showcase.Planogram.Planogram)
      pg.id
    end
  end

  describe "admin view" do
    test "shows model and prompt summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Admin") |> render_click()
      rendered = render(view)
      assert rendered =~ "claude-sonnet-4-5"
      assert rendered =~ "Vision model"
      assert rendered =~ "Default text model"
      assert rendered =~ Showcase.Common.Config.default_model()
    end
  end
end
