defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Seed
  alias Showcase.Repo

  setup do
    Mock.reset()
    RecruitFlow.register_mock_responses()
    Seed.seed()

    app = Repo.one(from a in Application, limit: 1) |> Repo.preload(:candidate)
    {:ok, %{app: app}}
  end

  test "renders the detail page", %{conn: conn, app: app} do
    {:ok, _view, html} = live(conn, "/recruit-flow/applications/#{app.id}")

    assert html =~ app.candidate.name
    assert html =~ "PENDING"
  end

  test "running AI screen transitions the application", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    updated = Repo.get!(Application, app.id)
    refute updated.state == "PENDING"
  end

  test "transition timeline shows audit log entries", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    html = render(view)
    assert html =~ "state_change"
  end
end
