defmodule ShowcaseWeb.Components.JSONInspector do
  use Phoenix.Component

  attr :data, :any, required: true
  attr :open, :boolean, default: false

  def json_inspector(assigns) do
    ~H"""
    <details open={@open} class="rounded border border-zinc-200 mt-3">
      <summary class="cursor-pointer px-3 py-2 text-xs uppercase tracking-wide text-zinc-500">
        Raw JSON
      </summary>
      <pre class="bg-zinc-900 text-zinc-50 text-xs p-3 overflow-auto"><%= Jason.encode!(@data, pretty: true) %></pre>
    </details>
    """
  end
end
