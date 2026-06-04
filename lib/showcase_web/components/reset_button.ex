defmodule ShowcaseWeb.Components.ResetButton do
  use Phoenix.Component

  attr :scope, :string, required: true, doc: ~s(Either "global" or a demo slug)
  attr :rest, :global

  def reset_button(assigns) do
    ~H"""
    <button
      type="button"
      class="rounded bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700"
      phx-click="reset"
      phx-value-scope={@scope}
      data-confirm={"Reset #{@scope}? This wipes demo data."}
      {@rest}
    >
      Reset <%= @scope %>
    </button>
    """
  end
end
