defmodule ShowcaseWeb.DashboardLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Dashboard
  alias ShowcaseWeb.Components.DemoTile

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Neurony AI Showcase")
     |> assign(:tiles, Dashboard.list_tiles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <a href="/" class="flex items-center gap-3">
            <span class="rounded bg-neurony-600 px-2 py-1 text-xs font-semibold text-white tracking-wider">
              NEURONY
            </span>
            <span class="text-sm font-medium text-zinc-700">AI Showcase</span>
          </a>
          <div class="flex items-center gap-4">
            <Layouts.theme_toggle />
            <a
              href="/admin/reset"
              class="text-sm text-zinc-500 underline hover:text-zinc-700"
            >
              Admin
            </a>
          </div>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <div class="mb-10">
          <h1 class="text-4xl font-semibold tracking-tight text-zinc-900">AI in production</h1>
          <p class="mt-3 text-base text-zinc-600 max-w-2xl">
            Five working demos showing how Neurony bakes AI into real business
            workflows. Each one runs a real Claude pipeline against synthetic
            input — the engineering is the same as production code.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <DemoTile.demo_tile :for={tile <- @tiles} tile={tile} />
        </div>
      </main>
    </div>
    """
  end
end
