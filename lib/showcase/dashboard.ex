defmodule Showcase.Dashboard do
  @moduledoc """
  Public context for the dashboard. Reads from `Showcase.Dashboard.TileConfig`
  and exposes a clean API for LiveViews and admin tools.

  Adding a new demo: edit `TileConfig`, not this module. This module's job is
  filtering and projecting the registry — not declaring demos.
  """

  alias Showcase.Dashboard.{Tile, TileConfig}

  @doc "All tiles in spec order."
  @spec list_tiles() :: list(Tile.t())
  def list_tiles, do: TileConfig.all()

  @doc "Only tiles marked :live (i.e., the demos that have shipped)."
  @spec live_tiles() :: list(Tile.t())
  def live_tiles, do: list_tiles() |> Enum.filter(&(&1.status == :live))

  @doc "Only tiles marked :coming_soon."
  @spec coming_soon_tiles() :: list(Tile.t())
  def coming_soon_tiles, do: list_tiles() |> Enum.filter(&(&1.status == :coming_soon))

  @doc "Find a tile by its id, or `nil`."
  @spec find_tile(atom()) :: Tile.t() | nil
  def find_tile(id) when is_atom(id), do: Enum.find(list_tiles(), &(&1.id == id))

  @doc """
  All seeder modules from live tiles. Used by the admin Reset orchestrator
  to enumerate seeders without hardcoding the list.
  """
  @spec live_seeders() :: list(module())
  def live_seeders do
    list_tiles()
    |> Enum.filter(&(&1.status == :live and not is_nil(&1.seeder)))
    |> Enum.map(& &1.seeder)
  end
end
