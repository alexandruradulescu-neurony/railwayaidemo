defmodule ShowcaseWeb.InvoiceApproval.BundleDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  import Phoenix.LiveViewTest

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval
  alias Showcase.InvoiceApproval.Schemas.Verdict
  alias Showcase.InvoiceApproval.Seed
  alias Showcase.Repo

  setup do
    Mock.reset()
    InvoiceApproval.register_mock_responses()
    Seed.seed()

    bundle = Repo.get_by!(Showcase.InvoiceApproval.Schemas.DocumentBundle, scenario: "clean_match")

    # Pre-run pipeline so there's a verdict
    {:ok, _} = InvoiceApproval.enqueue(bundle.id)
    Oban.drain_queue(queue: :invoice_approval)

    {:ok, %{bundle: bundle}}
  end

  test "renders the bundle detail page", %{conn: conn, bundle: bundle} do
    {:ok, _view, html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    assert html =~ "Bundle ##{bundle.id}"
    assert html =~ "K1001-07-n03"
  end

  test "shows the latest verdict outcome", %{conn: conn, bundle: bundle} do
    {:ok, _view, html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    assert html =~ "approve"
  end

  test "updating thresholds creates a new verdict with the new thresholds_used",
       %{conn: conn, bundle: bundle} do
    {:ok, view, _html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    initial_count = Repo.aggregate(Verdict, :count, :id)

    render_change(view, "update_thresholds", %{
      "price_pct" => "10.0",
      "qty_pct" => "5.0",
      "date_days" => "7"
    })

    assert Repo.aggregate(Verdict, :count, :id) == initial_count + 1

    new_latest = InvoiceApproval.latest_verdict(bundle.id)
    assert new_latest.thresholds_used == %{"price_pct" => 10.0, "qty_pct" => 5.0, "date_days" => 7}
    assert new_latest.source == "ai"
  end

  test "override creates a new verdict with source: 'override' + audit log", %{conn: conn, bundle: bundle} do
    {:ok, view, _html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    render_click(view, "override", %{"outcome" => "reject", "reason" => "manual reject"})

    new_latest = InvoiceApproval.latest_verdict(bundle.id)
    assert new_latest.source == "override"
    assert new_latest.outcome == "reject"
    assert new_latest.reasoning =~ "manual reject"

    # Audit log entry written
    {:ok, audit_entries} =
      Showcase.Common.AuditLog.for_entity("invoice_approval", "bundle", to_string(bundle.id))

    assert Enum.any?(audit_entries, &(&1.event == "verdict_override"))
  end
end
