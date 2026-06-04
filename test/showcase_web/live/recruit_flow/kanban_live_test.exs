defmodule ShowcaseWeb.RecruitFlow.KanbanLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.RecruitFlow.Seed

  setup do
    Showcase.Common.AnthropicClient.Mock.reset()
    Showcase.RecruitFlow.register_mock_responses()
    Seed.seed()
    :ok
  end

  test "renders the 5-column board", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/recruit-flow")

    assert html =~ "RecruitFlow"
    assert html =~ "PENDING"
    assert html =~ "QUALIFIED"
    assert html =~ "HIRED"
    assert html =~ "REJECTED"
    assert html =~ "NEEDS_HUMAN"
    assert html =~ "Alice Anderson"
  end

  test "running AI screen transitions an application", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/recruit-flow")

    apps = Showcase.RecruitFlow.applications_by_state()
    pending = Map.get(apps, "PENDING", [])
    first = hd(pending)

    render_click(view, "run_ai_screen", %{"id" => first.id, "scenario" => "alice_qualified"})

    # Phone screen completes synchronously through the Mock, so the test should see
    # the transition reflected after the click.
    updated = Showcase.RecruitFlow.find_application(first.id)
    refute updated.state == "PENDING"
  end
end
