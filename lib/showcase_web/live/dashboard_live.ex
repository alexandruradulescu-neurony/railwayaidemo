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
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <a href="/" class="flex items-center gap-3 text-ink">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a
            href="/admin/reset"
            class="text-sm text-ink/60 hover:text-purple transition-colors"
          >
            Admin
          </a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-12">
        <div class="mb-10">
          <p class="font-body font-bold text-sm uppercase tracking-wider text-purple">
            Neurony · AI Showcase
          </p>
          <h1 class="mt-2 font-heading font-bold text-5xl text-ink tracking-tight">
            AI in production
          </h1>
          <p class="mt-3 font-body text-lg text-ink/70 max-w-2xl">
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
