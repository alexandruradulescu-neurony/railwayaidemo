defmodule ShowcaseWeb.Admin.AuditLogLive do
  use ShowcaseWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Audit log (admin)")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-xl font-semibold">Audit log</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Audit log viewer arrives in a later phase.
      </p>
    </div>
    """
  end
end
