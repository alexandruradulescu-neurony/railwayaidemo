defmodule ShowcaseWeb.Components.CascadeMatrix do
  use Phoenix.Component

  alias Showcase.Common.CascadeMatcher.Outcome

  attr :outcome, Outcome, required: true
  attr :class, :string, default: ""

  def cascade_matrix(assigns) do
    ~H"""
    <div class={["rounded border border-zinc-200 p-3", @class]}>
      <p class="text-xs uppercase tracking-wide text-zinc-500 mb-2">
        Match cascade — <%= length(@outcome.attempts) %> step(s)
      </p>
      <ol class="space-y-1 text-sm">
        <li :for={attempt <- @outcome.attempts}>
          <span class="font-mono"><%= attempt.step %></span>:
          <span><%= inspect(attempt.result) %></span>
        </li>
      </ol>
    </div>
    """
  end
end
