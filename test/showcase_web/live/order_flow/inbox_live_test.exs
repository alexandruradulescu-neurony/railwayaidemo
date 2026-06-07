defmodule ShowcaseWeb.OrderFlow.InboxLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.{Seed, Schemas.SyntheticMessage}
  alias Showcase.Repo

  setup do
    Seed.seed()
    :ok
  end

  test "mounts and renders the inbox with the Write-email button", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/order-flow")

    assert html =~ "OrderFlow"
    assert html =~ "Write an email"
    assert html =~ "Inbox"
    assert html =~ "Pipeline"
  end

  test "shows seeded messages in the inbox (subject + from)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")
    rendered = render(view)

    # Seeded messages should show their subject + from_address in the list
    assert rendered =~ "Comandă mânere"
    assert rendered =~ "alexandru.erdei@meesenburg.ro"
  end

  test "selecting a message opens the reader with body + analyze button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    msg = Repo.get_by!(SyntheticMessage, scenario: "meesenburg_clean_sku")

    rendered =
      view
      |> element("button[phx-click='select_message'][phx-value-id='#{msg.id}']")
      |> render_click()

    assert rendered =~ "K1001-07-n03"
    assert rendered =~ "Analyze"
  end

  test "analyze button enqueues an Oban job", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")
    msg = Repo.get_by!(SyntheticMessage, scenario: "meesenburg_clean_sku")

    # Select first so the reader is open
    view
    |> element("button[phx-click='select_message'][phx-value-id='#{msg.id}']")
    |> render_click()

    # Now click analyze
    view
    |> element("button[phx-click='analyze_message'][phx-value-id='#{msg.id}']")
    |> render_click()

    Oban.drain_queue(queue: :order_flow)

    # After draining, the message has an associated order
    assert OrderFlow.order_for_message(msg.id) != nil
  end

  test "open_compose shows the compose modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    rendered =
      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

    assert rendered =~ "New email"
    assert rendered =~ "orders@orderflow.com"  # placeholder
  end

  test "send_compose inserts a composed message that lands in the inbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    view
    |> element("button[phx-click='open_compose']")
    |> render_click()

    rendered =
      view
      |> form("form[phx-submit='send_compose']", %{
        "compose" => %{
          "from_address" => "buyer@example.test",
          "subject" => "Compose smoke test",
          "body" => "Need 10 widgets"
        }
      })
      |> render_submit()

    assert rendered =~ "Compose smoke test"
    assert rendered =~ "buyer@example.test"

    # Verify it landed in DB
    composed = Repo.all(from m in SyntheticMessage, where: m.composed == true)
    assert length(composed) == 1
  end
end
