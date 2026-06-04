defmodule ShowcaseWeb.Components.DemoTile do
  @moduledoc """
  Renders one dashboard tile.

  Two visual variants based on `tile.status`:
    * `:live` — clickable, "Open →" link to `tile.path`, green "Live" badge.
    * `:coming_soon` — grayed out, no link, "Coming soon" badge.

  Both variants show title, description, and ROI hook.
  """

  use Phoenix.Component

  alias Showcase.Dashboard.Tile

  attr :tile, Tile, required: true

  def demo_tile(%{tile: %Tile{status: :live}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      class="block rounded-lg border border-zinc-200 bg-white p-6 shadow-sm transition hover:shadow-md hover:border-emerald-300"
    >
      <div class="flex items-start justify-between mb-3">
        <h3 class="text-lg font-semibold text-zinc-900">{@tile.title}</h3>
        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-emerald-300">
          <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
          Live
        </span>
      </div>
      <p class="text-sm text-zinc-700 mb-3">{@tile.description}</p>
      <p class="text-xs text-zinc-500 italic mb-4">{@tile.roi_hook}</p>
      <p class="text-sm font-medium text-emerald-700">Open →</p>
    </a>
    """
  end

  def demo_tile(%{tile: %Tile{status: :coming_soon}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-6 shadow-sm opacity-75">
      <div class="flex items-start justify-between mb-3">
        <h3 class="text-lg font-semibold text-zinc-700">{@tile.title}</h3>
        <span class="inline-flex items-center rounded-full bg-zinc-200 px-2 py-0.5 text-xs font-medium text-zinc-700 ring-1 ring-zinc-300">
          Coming soon
        </span>
      </div>
      <p class="text-sm text-zinc-600 mb-3">{@tile.description}</p>
      <p class="text-xs text-zinc-500 italic">{@tile.roi_hook}</p>
    </div>
    """
  end
end
