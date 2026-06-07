defmodule ShowcaseWeb.Components.DemoTile do
  @moduledoc """
  Renders one dashboard tile.

  Two visual variants based on `tile.status`:
    * `:live` — clickable, "Open →" link to `tile.path`, green "Live" badge.
    * `:coming_soon` — surface-lav background, no link, neutral "Coming soon" badge.

  Both variants show title, description, and ROI hook.
  """

  use Phoenix.Component

  alias Showcase.Dashboard.Tile

  attr :tile, Tile, required: true

  def demo_tile(%{tile: %Tile{status: :live}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      class="block rounded-2xl border border-line bg-white p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
    >
      <div class="flex items-start justify-between mb-3">
        <h3 class="font-heading font-bold text-lg text-ink">{@tile.title}</h3>
        <span class="inline-flex items-center gap-1.5 rounded-full bg-green/10 px-2.5 py-0.5 text-xs font-medium text-green ring-1 ring-green/30">
          <span class="h-1.5 w-1.5 rounded-full bg-green"></span> Live
        </span>
      </div>
      <p class="font-body text-sm text-ink/80 mb-3">{@tile.description}</p>
      <p class="font-body text-xs italic text-ink/50 mb-4">{@tile.roi_hook}</p>
      <p class="font-body text-sm font-semibold text-purple">Open →</p>
    </a>
    """
  end

  def demo_tile(%{tile: %Tile{status: :coming_soon}} = assigns) do
    ~H"""
    <div class="rounded-2xl border border-line bg-surface-lav p-6 opacity-75">
      <div class="flex items-start justify-between mb-3">
        <h3 class="font-heading font-bold text-lg text-ink/70">{@tile.title}</h3>
        <span class="inline-flex items-center rounded-full bg-line/40 px-2.5 py-0.5 text-xs font-medium text-ink/60 ring-1 ring-line">
          Coming soon
        </span>
      </div>
      <p class="font-body text-sm text-ink/60 mb-3">{@tile.description}</p>
      <p class="font-body text-xs italic text-ink/50">{@tile.roi_hook}</p>
    </div>
    """
  end
end
