defmodule ShowcaseWeb.Components.PipelineStages do
  use Phoenix.Component

  attr :stages, :list, required: true,
    doc: ~s(List of %{label: ..., status: :pending|:running|:done|:failed})

  def pipeline_stages(assigns) do
    ~H"""
    <ol class="flex items-center gap-2">
      <li :for={stage <- @stages} class={[
        "flex items-center gap-2 rounded px-3 py-2 text-xs",
        stage.status == :pending && "bg-zinc-100 text-zinc-500",
        stage.status == :running && "bg-blue-100 text-blue-900 animate-pulse",
        stage.status == :done && "bg-emerald-100 text-emerald-900",
        stage.status == :failed && "bg-red-100 text-red-900"
      ]}>
        <span class="font-medium"><%= stage.label %></span>
      </li>
    </ol>
    """
  end
end
