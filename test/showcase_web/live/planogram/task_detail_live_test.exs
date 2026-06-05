defmodule ShowcaseWeb.Planogram.TaskDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo
  import Phoenix.LiveViewTest

  alias Showcase.Planogram
  alias Showcase.Planogram.{Seed, MockPrompts, VerificationTask, Worker}
  alias Showcase.Repo

  setup do
    Seed.seed()
    MockPrompts.register_all()
    :ok
  end

  describe "pending task" do
    test "shows the planogram name + Run analysis button", %{conn: conn} do
      task = a_task("compliant")
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Downtown Mart"
      assert html =~ "Run analysis"
      assert html =~ "pending"
    end
  end

  describe "complete task" do
    test "renders compliance gauge, per-row, issues, suggestions, cost badge", %{conn: conn} do
      task = a_task("compliant") |> run_to_completion()

      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "96%"                          # gauge
      assert html =~ "Top shelf"                    # per-row
      assert html =~ "Shelf matches planogram"      # exec summary
      assert html =~ "no action needed"             # suggestion
      assert html =~ "tok"                          # CostBadge
      assert html =~ "Raw JSON"                     # JSONInspector
    end

    test "major_issues result renders high-severity issue rows", %{conn: conn} do
      task = a_task("major_issues") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Sprite 500ml MISSING"
      assert html =~ "high"
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
    {:ok, _} = Planogram.enqueue_analysis(task.id)
    [job] = all_enqueued()
    perform_job(Worker, job.args)
    Repo.get!(VerificationTask, task.id)
  end
end
