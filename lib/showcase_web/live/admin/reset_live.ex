defmodule ShowcaseWeb.Admin.ResetLive do
  use ShowcaseWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Reset (admin)")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-xl font-semibold">Reset demo data</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Per-demo + global reset arrives in a later phase.
      </p>
    </div>
    """
  end
end
