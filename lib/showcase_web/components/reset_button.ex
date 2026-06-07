defmodule ShowcaseWeb.Components.ResetButton do
  use Phoenix.Component

  attr :scope, :string, required: true, doc: ~s(Either "global" or a demo slug)
  attr :rest, :global

  def reset_button(assigns) do
    ~H"""
    <button
      type="button"
      class="rounded-lg bg-red px-3 py-2 font-body text-sm font-semibold text-white shadow-sm transition hover:bg-red/90 active:bg-red/95"
      phx-click="reset"
      phx-value-scope={@scope}
      data-confirm={"Reset #{@scope}? This wipes demo data."}
      {@rest}
    >
      Reset {@scope}
    </button>
    """
  end
end
