defmodule ShowcaseWeb.OrderFlow.OrderDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Schemas.{Client, Order, OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  setup do
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, order} =
      %Order{}
      |> Order.changeset(%{client_id: client.id, status: "pending_review"})
      |> Repo.insert()

    {:ok, order_line} =
      %OrderLine{}
      |> OrderLine.changeset(%{
        order_id: order.id,
        product_id: nil,
        raw_description: "mystery thing",
        quantity: 3,
        confidence: nil,
        match_step: nil
      })
      |> Repo.insert()

    {:ok, %{order: order, client: client, order_line: order_line, widget: widget}}
  end

  test "renders order with unmatched lines and a correction dropdown",
       %{conn: conn, order: order} do
    {:ok, _view, html} = live(conn, "/order-flow/orders/#{order.id}")

    assert html =~ "mystery thing"
    assert html =~ "Correct"
  end

  test "submitting a correction updates the line and writes a ProductAlias",
       %{conn: conn, order: order, client: client, order_line: line, widget: widget} do
    {:ok, view, _html} = live(conn, "/order-flow/orders/#{order.id}")

    render_change(view, "correct_line", %{
      "line_id" => line.id,
      "product_id" => widget.id
    })

    updated_line = Repo.get!(OrderLine, line.id)
    assert updated_line.product_id == widget.id

    alias_row =
      Repo.get_by!(ProductAlias,
        normalized_text: "mystery thing",
        client_id: client.id,
        product_id: widget.id
      )

    assert alias_row.source == "correction"
    assert alias_row.confidence >= 0.85
  end

  test "promotes to a global alias when ≥2 distinct clients have corrected the same mapping",
       %{conn: conn, order: order, order_line: line, widget: widget} do
    # Pre-seed: a correction from a different client already exists with high confidence.
    {:ok, other_client} = Repo.insert(%Client{name: "Other Co"})

    %ProductAlias{}
    |> ProductAlias.changeset(%{
      normalized_text: "mystery thing",
      product_id: widget.id,
      client_id: other_client.id,
      confidence: 0.9,
      last_used_at: DateTime.utc_now(),
      use_count: 1,
      source: "correction"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/order-flow/orders/#{order.id}")

    render_change(view, "correct_line", %{
      "line_id" => line.id,
      "product_id" => widget.id
    })

    # After the correction: 2 distinct clients now have the mapping with high confidence.
    # A global alias (client_id: nil) should have been created.
    # Use is_nil/1 since Ecto refuses `client_id: nil` in keyword filters.
    global =
      Repo.one(
        from a in ProductAlias,
          where:
            a.normalized_text == "mystery thing" and
              a.product_id == ^widget.id and
              is_nil(a.client_id)
      )

    assert global != nil
    assert global.source == "promotion"
    assert global.confidence >= 0.7
  end
end
