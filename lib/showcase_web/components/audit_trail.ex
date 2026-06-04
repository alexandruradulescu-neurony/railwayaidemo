defmodule ShowcaseWeb.Components.AuditTrail do
  use Phoenix.Component

  attr :entries, :list, required: true

  def audit_trail(assigns) do
    ~H"""
    <ol class="space-y-2">
      <li :for={entry <- @entries} class="text-sm border-l-2 border-zinc-200 pl-3">
        <p class="font-medium"><%= entry.event %></p>
        <p class="text-xs text-zinc-500"><%= entry.inserted_at %></p>
      </li>
    </ol>
    """
  end
end
