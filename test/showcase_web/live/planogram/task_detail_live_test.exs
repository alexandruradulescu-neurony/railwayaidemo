defmodule ShowcaseWeb.Planogram.TaskDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo
  import Phoenix.LiveViewTest

  alias Showcase.Planogram
  alias Showcase.Planogram.{Seed, MockPrompts, VerificationTask, Worker}
  alias Showcase.Repo

  @test_photo "/uploads/planogram/test-shelf.png"

  setup do
    Seed.seed()
    MockPrompts.register_all()

    # Worker requires a real photo on disk — no more bundled fallback.
    File.mkdir_p!("priv/static/uploads/planogram")
    File.write!(
      "priv/static" <> @test_photo,
      <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>
    )

    :ok
  end

  describe "pending task" do
    test "shows the planogram name + Upload & analyze button", %{conn: conn} do
      task = a_task("compliant")
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Downtown Mart"
      assert html =~ "Upload &amp; analyze"
      assert html =~ "pending"
    end

    test "shows reference planogram image + shelf upload form", %{conn: conn} do
      task = a_task("compliant") |> Repo.preload(:planogram)
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Reference planogram"
      assert html =~ "Upload shelf photo"
      assert html =~ task.planogram.reference_image_path
    end

    test "uploading a shelf photo updates the task's photo_path", %{conn: conn} do
      task = a_task("compliant")
      {:ok, view, _html} = live(conn, "/planogram/#{task.id}")

      png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>

      photo =
        file_input(view, "form[phx-submit='upload_shelf']", :shelf, [
          %{
            last_modified: 1_700_000_000_000,
            name: "shelf.png",
            content: png_bytes,
            type: "image/png"
          }
        ])

      assert render_upload(photo, "shelf.png") =~ "shelf.png"

      view
      |> form("form[phx-submit='upload_shelf']")
      |> render_submit()

      updated = Repo.get!(VerificationTask, task.id)
      assert updated.photo_path =~ "/uploads/planogram/"
    end
  end

  describe "complete task" do
    test "renders compliance gauge, per-row, suggestions, cost badge", %{conn: conn} do
      task = a_task("compliant") |> run_to_completion()

      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "96%"                          # gauge
      assert html =~ "Top shelf"                    # per-row
      assert html =~ "matches"                      # exec summary (model-agnostic wording)
      assert html =~ "no action needed"             # suggestion
      assert html =~ "tok"                          # CostBadge
      assert html =~ "Raw JSON"                     # JSONInspector
    end

    test "major_issues result renders high-severity issues + out-of-stock", %{conn: conn} do
      task = a_task("major_issues") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "high"            # severity
      assert html =~ "out_of_stock"    # new categorized issue type
    end

    test "renders stats sidebar (Mismatches Found, Price Tags Verified)", %{conn: conn} do
      task = a_task("minor_issues") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Compliance Score"
      assert html =~ "Mismatches Found"
      assert html =~ "Price Tags Verified"
      assert html =~ "AI Analysis"
    end

    test "renders extracted price overlay badges with RON values", %{conn: conn} do
      task = a_task("compliant") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "RON 15.99"
      assert html =~ "Shelf compliance"
    end

    test "renders issue overlay badges with type labels", %{conn: conn} do
      task = a_task("major_issues") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      # ResultRenderer.issue_badge/1 maps types → UPPERCASE labels
      assert html =~ "OUT OF STOCK"
    end
  end

  describe "partial result (force truncation)" do
    test "renders a 'partial salvage' banner when result.partial? is true", %{conn: conn} do
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "compliant",
        text: ~s|{"compliance_score": 75, "rows": [{"name":"Top|,
        stop_reason: "max_tokens",
        input_tokens: 100,
        output_tokens: 50
      )

      task = a_task("compliant")

      {:ok, task} =
        task
        |> VerificationTask.changeset(%{photo_path: @test_photo})
        |> Repo.update()

      {:ok, _} = Planogram.enqueue_analysis(task.id, max_tokens: 200)
      [job] = all_enqueued()
      perform_job(Worker, job.args)

      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "response was truncated"  # partial banner copy
      assert html =~ "75%"
    end
  end

  defp a_task(scenario) do
    Repo.get_by!(VerificationTask, scenario: scenario)
  end

  defp run_to_completion(task) do
    {:ok, task} =
      task
      |> VerificationTask.changeset(%{photo_path: @test_photo})
      |> Repo.update()

    {:ok, _} = Planogram.enqueue_analysis(task.id)
    [job] = all_enqueued()
    perform_job(Worker, job.args)
    Repo.get!(VerificationTask, task.id)
  end
end
