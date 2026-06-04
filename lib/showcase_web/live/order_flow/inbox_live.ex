defmodule ShowcaseWeb.OrderFlow.InboxLive do
  use ShowcaseWeb, :live_view

  alias Showcase.OrderFlow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Mock responses are registered once per LiveView mount in non-prod envs
      # (test env uses test setup; this is a safety net for dev demo).
      if Mix.env() != :prod do
        OrderFlow.register_mock_responses()
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "OrderFlow")
     |> assign(:messages, OrderFlow.list_messages())
     |> assign(:orders, OrderFlow.list_orders())
     |> assign(:active_message, nil)
     |> assign(:active_stages, initial_stages())
     |> assign(:active_lines, [])
     |> assign(:cascade_detail_open, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 p-6 min-h-screen">
      <section class="border rounded p-4">
        <header class="flex items-center justify-between mb-4">
          <h1 class="text-xl font-semibold">OrderFlow</h1>
          <button
            type="button"
            class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
            phx-click="generate_order"
          >
            Generate order
          </button>
        </header>

        <ol class="space-y-2">
          <li :for={msg <- @messages} class="text-sm border-l-2 border-zinc-200 pl-3">
            <p class="font-medium">{msg.client_hint || "(no client hint)"} · <span class="text-zinc-500">{msg.kind}</span></p>
            <p class="text-zinc-700 mt-1">{msg.body}</p>
          </li>
        </ol>
      </section>

      <section class="border rounded p-4">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Pipeline</h2>
        <%= if @active_message do %>
          <p class="text-sm text-zinc-700 mb-3">Processing: <span class="font-mono">{@active_message.scenario}</span></p>
        <% else %>
          <p class="text-sm text-zinc-500">Click "Generate order" to start.</p>
        <% end %>

        <%!-- stages and lines render in Task 17 --%>
      </section>
    </div>
    """
  end

  defp initial_stages do
    [
      %{label: "Extract", status: :pending},
      %{label: "Identify client", status: :pending},
      %{label: "Match lines", status: :pending},
      %{label: "Create order", status: :pending}
    ]
  end
end
