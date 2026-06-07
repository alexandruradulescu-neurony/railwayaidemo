defmodule ShowcaseWeb.Components.AuditTrail do
  use Phoenix.Component

  attr :entries, :list, required: true

  def audit_trail(assigns) do
    ~H"""
    <ol class="space-y-2">
      <li :for={entry <- @entries} class="text-sm border-l-2 border-line pl-3">
        <p class="font-body font-medium text-ink">{entry.event}</p>
        <p class="font-body text-xs text-ink/50">{entry.inserted_at}</p>
      </li>
    </ol>
    """
  end
end
