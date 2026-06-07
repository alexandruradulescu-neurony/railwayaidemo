defmodule ShowcaseWeb.Components.CostBadge do
  use Phoenix.Component

  alias Showcase.Common.AnthropicClient.Types.Usage

  attr :usage, Usage, required: true

  def cost_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 rounded border border-line bg-white px-2 py-1 text-xs text-ink/70">
      <span>{@usage.input_tokens + @usage.output_tokens} tok</span>
      <span class="text-ink/40">·</span>
      <span class="font-semibold text-purple">
        ≈ {:erlang.float_to_binary(@usage.cost_estimate_cents, decimals: 2)}¢
      </span>
    </span>
    """
  end
end
