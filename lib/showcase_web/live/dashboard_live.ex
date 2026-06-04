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
          <div>
            <h1 class="text-2xl font-semibold text-zinc-900">Neurony AI Showcase</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Live demos of AI-mediated workflows we've built for clients.
            </p>
          </div>
          <a
            href="/admin/reset"
            class="text-sm text-zinc-500 underline hover:text-zinc-700"
          >
            Admin
          </a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <DemoTile.demo_tile :for={tile <- @tiles} tile={tile} />
        </div>
      </main>
    </div>
    """
  end
end
