defmodule Showcase.Dashboard.TileConfigTest do
  use ExUnit.Case, async: true

  alias Showcase.Dashboard.{Tile, TileConfig}

  describe "all/0" do
    test "returns exactly 5 tiles in spec order" do
      tiles = TileConfig.all()
      assert length(tiles) == 5

      ids = Enum.map(tiles, & &1.id)
      assert ids == [:order_flow, :recruit_flow, :planogram, :invoice_approval, :restaurant_compliance]
    end

    test "every tile is a %Tile{} struct" do
      Enum.each(TileConfig.all(), fn tile ->
        assert match?(%Tile{}, tile)
      end)
    end

    test "every tile has required fields populated" do
      Enum.each(TileConfig.all(), fn tile ->
        assert is_atom(tile.id)
        assert is_binary(tile.title)
        assert is_binary(tile.description)
        assert is_binary(tile.roi_hook)
        assert tile.status in [:live, :coming_soon]
      end)
    end

    test "OrderFlow and Invoice Approval are live" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      assert by_id[:order_flow].status == :live
      assert by_id[:order_flow].path == "/order-flow"
      assert by_id[:order_flow].seeder == Showcase.OrderFlow.Seed

      assert by_id[:invoice_approval].status == :live
      assert by_id[:invoice_approval].path == "/invoice-approval"
      assert by_id[:invoice_approval].seeder == Showcase.InvoiceApproval.Seed
    end

    test "RecruitFlow, Planogram, Restaurant Compliance are coming_soon" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      Enum.each([:recruit_flow, :planogram, :restaurant_compliance], fn id ->
        assert by_id[id].status == :coming_soon
        assert by_id[id].path == nil
        assert by_id[id].seeder == nil
      end)
    end
  end
end
