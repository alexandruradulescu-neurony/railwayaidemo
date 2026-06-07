defmodule ShowcaseWeb.Planogram.Components.ComplianceGauge do
  @moduledoc """
  SVG circular gauge for the compliance score. Color-coded by percentage:

    * `>= 90` — emerald (compliant)
    * `>= 60` — amber (partial)
    * `< 60`  — rose (non-compliant)
  """
  use Phoenix.Component

  attr :pct, :integer, required: true
  attr :size, :integer, default: 140

  def compliance_gauge(assigns) do
    radius = div(assigns.size, 2) - 8
    circumference = 2 * :math.pi() * radius
    dash = circumference * (1 - assigns.pct / 100)

    color =
      cond do
        assigns.pct >= 90 -> "stroke-emerald-500"
        assigns.pct >= 60 -> "stroke-amber-500"
        true -> "stroke-rose-500"
      end

    assigns =
      assigns
      |> assign(:radius, radius)
      |> assign(:circumference, circumference)
      |> assign(:dash, dash)
      |> assign(:color, color)
      |> assign(:cx, div(assigns.size, 2))
      |> assign(:cy, div(assigns.size, 2))

    ~H"""
    <div class="relative inline-block" style={"width: #{@size}px; height: #{@size}px"}>
      <svg width={@size} height={@size} viewBox={"0 0 #{@size} #{@size}"}>
        <circle cx={@cx} cy={@cy} r={@radius} class="stroke-line" stroke-width="10" fill="none"/>
        <circle cx={@cx} cy={@cy} r={@radius}
                class={["transition-all", @color]} stroke-width="10" fill="none"
                stroke-linecap="round"
                stroke-dasharray={"#{Float.round(@circumference, 2)}"}
                stroke-dashoffset={"#{Float.round(@dash, 2)}"}
                transform={"rotate(-90 #{@cx} #{@cy})"}/>
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-3xl font-semibold"><%= @pct %>%</span>
      </div>
    </div>
    """
  end
end
