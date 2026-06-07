defmodule ShowcaseWeb.Components.CostBadge do
  use Phoenix.Component

  alias Showcase.Common.AnthropicClient.Types.Usage

  attr :usage, Usage, required: true

  attr :source, :string,
    default: "live",
    doc:
      "\"mock\" (free, scripted demo response) or \"live\" (real Claude call). " <>
        "Mock renders a `(scripted)` tag and zeros the cost so the demo doesn't " <>
        "advertise tokens we never burnt."

  def cost_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 rounded border border-line bg-white px-2 py-1 text-xs text-ink/70">
      <span>{@usage.input_tokens + @usage.output_tokens} tok</span>
      <span class="text-ink/40">·</span>
      <%= if @source == "mock" do %>
        <span class="font-semibold text-ink/50" title="Scripted demo response — no API call was made.">
          (scripted)
        </span>
      <% else %>
        <span class="font-semibold text-purple">
          ≈ {:erlang.float_to_binary(@usage.cost_estimate_cents, decimals: 2)}¢
        </span>
      <% end %>
    </span>
    """
  end
end
