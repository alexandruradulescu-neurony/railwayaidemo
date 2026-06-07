defmodule ShowcaseWeb.Planogram.MobileCaptureLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Showcase.Planogram.{Seed, VerificationTask}
  alias Showcase.Repo

  setup do
    Seed.seed()
    :ok
  end

  describe "GET /planogram/mobile/:token" do
    test "renders the capture UI when token is valid", %{conn: conn} do
      task = first_pending_task()
      {:ok, _view, html} = live(conn, "/planogram/mobile/#{task.mobile_token}")
      assert html =~ task.store_name
      assert html =~ "Capture photo"
    end

    test "renders an error when token is unknown", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/planogram/mobile/not-a-real-token")
      assert html =~ "Link is no longer valid"
    end

    test "renders 'already processed' when task is complete", %{conn: conn} do
      task = first_pending_task()

      task
      |> VerificationTask.changeset(%{status: "complete"})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, "/planogram/mobile/#{task.mobile_token}")
      assert html =~ "already been processed"
    end
  end

  defp first_pending_task do
    # Prod seed has 2 "compliant" tasks (pharmacy + juices). Either works.
    import Ecto.Query, only: [from: 2]
    Repo.one!(from t in VerificationTask, where: t.scenario == "compliant", limit: 1)
  end
end
