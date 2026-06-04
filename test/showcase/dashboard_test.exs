defmodule Showcase.DashboardTest do
  use ExUnit.Case, async: true

  alias Showcase.Dashboard
  alias Showcase.Dashboard.Tile

  describe "list_tiles/0" do
    test "returns all 5 tiles" do
      assert length(Dashboard.list_tiles()) == 5
    end
  end

  describe "live_tiles/0" do
    test "returns only :live tiles" do
      live = Dashboard.live_tiles()
      assert length(live) >= 1
      Enum.each(live, fn t -> assert t.status == :live end)
    end

    test "includes OrderFlow" do
      assert Enum.any?(Dashboard.live_tiles(), &(&1.id == :order_flow))
    end
  end

  describe "coming_soon_tiles/0" do
    test "returns only :coming_soon tiles" do
      cs = Dashboard.coming_soon_tiles()
      Enum.each(cs, fn t -> assert t.status == :coming_soon end)
    end

    test "excludes OrderFlow" do
      refute Enum.any?(Dashboard.coming_soon_tiles(), &(&1.id == :order_flow))
    end
  end

  describe "find_tile/1" do
    test "returns the tile when found" do
      assert %Tile{id: :order_flow} = Dashboard.find_tile(:order_flow)
    end

    test "returns nil when not found" do
      assert Dashboard.find_tile(:nonexistent) == nil
    end
  end

  describe "live_seeders/0" do
    test "returns seeder modules for all :live tiles" do
      seeders = Dashboard.live_seeders()
      assert Showcase.OrderFlow.Seed in seeders
    end

    test "excludes nil seeders from coming_soon tiles" do
      refute nil in Dashboard.live_seeders()
    end
  end
end
