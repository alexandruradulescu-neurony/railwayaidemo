defmodule ShowcaseWeb.Components.NeedsHumanBadge do
  use Phoenix.Component

  alias Showcase.Common.NeedsHuman.Decision

  attr :decision, Decision, required: true
  attr :class, :string, default: ""

  def needs_human_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-medium",
      @decision.needs_review? && "bg-amber-100 text-amber-900 ring-1 ring-amber-300",
      !@decision.needs_review? && "bg-emerald-100 text-emerald-900 ring-1 ring-emerald-300",
      @class
    ]}>
      <%= if @decision.needs_review? do %>
        ⚠ Needs review
      <% else %>
        ✓ Confident
      <% end %>
    </span>
    """
  end
end
