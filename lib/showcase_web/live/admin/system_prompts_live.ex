defmodule ShowcaseWeb.Admin.SystemPromptsLive do
  use ShowcaseWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "System Prompts (admin)")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-xl font-semibold">System Prompts</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Admin UI for live-editing prompts arrives in a later phase.
      </p>
    </div>
    """
  end
end
