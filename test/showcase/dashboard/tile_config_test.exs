defmodule Showcase.Dashboard.TileConfigTest do
  use ExUnit.Case, async: true

  alias Showcase.Dashboard.{Tile, TileConfig}

  describe "all/0" do
    test "returns exactly 5 tiles in spec order" do
      tiles = TileConfig.all()
      assert length(tiles) == 5

      ids = Enum.map(tiles, & &1.id)
      # Demo-flow order: OrderFlow → Invoice → Planogram → Restaurant → RecruitFlow (coming soon, last).
      assert ids == [:order_flow, :invoice_approval, :planogram, :restaurant_compliance, :recruit_flow]
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

    test "four demos are live + RecruitFlow is coming_soon, all with path + seeder wired" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      assert by_id[:order_flow].status == :live
      assert by_id[:invoice_approval].status == :live
      assert by_id[:planogram].status == :live
      assert by_id[:planogram].path == "/planogram"
      assert by_id[:planogram].seeder == Showcase.Planogram.Seed
      assert by_id[:restaurant_compliance].status == :live
      assert by_id[:restaurant_compliance].path == "/restaurant-compliance"
      assert by_id[:restaurant_compliance].seeder == Showcase.RestaurantCompliance.Seed
      # RecruitFlow deferred: tile renders as "Coming soon" and is not clickable
      # from the dashboard, but path + seeder stay wired for the eventual flip.
      assert by_id[:recruit_flow].status == :coming_soon
      assert by_id[:recruit_flow].path == "/recruit-flow"
      assert by_id[:recruit_flow].seeder == Showcase.RecruitFlow.Seed
    end
  end
end
