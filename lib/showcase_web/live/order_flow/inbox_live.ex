defmodule ShowcaseWeb.OrderFlow.InboxLive do
  use ShowcaseWeb, :live_view

  alias Showcase.OrderFlow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
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
  def handle_event("generate_order", _params, socket) do
    case OrderFlow.enqueue_random() do
      {:ok, _job, msg} ->
        topic = "order_flow:processing:#{msg.id}"
        Phoenix.PubSub.subscribe(Showcase.PubSub, topic)

        {:noreply,
         socket
         |> assign(:active_message, msg)
         |> assign(:active_stages, [
           %{label: "Extract", status: :running},
           %{label: "Identify client", status: :pending},
           %{label: "Match lines", status: :pending},
           %{label: "Create order", status: :pending}
         ])
         |> assign(:active_lines, [])}

      {:error, :no_messages} ->
        {:noreply, put_flash(socket, :info, "All messages processed — reset OrderFlow to start over.")}
    end
  end

  def handle_event("toggle_cascade_detail", _params, socket) do
    {:noreply, update(socket, :cascade_detail_open, &(!&1))}
  end

  @impl true
  def handle_info({:order_flow, :extracted, payload}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       List.update_at(stages, 0, &Map.put(&1, :status, :done))
       |> List.update_at(1, &Map.put(&1, :status, :running))
     end)
     |> put_flash(:info, "Extracted #{payload.line_count} line(s); hint: #{payload.client_hint}")}
  end

  def handle_info({:order_flow, :client_identified, _payload}, socket) do
    {:noreply,
     update(socket, :active_stages, fn stages ->
       List.update_at(stages, 1, &Map.put(&1, :status, :done))
       |> List.update_at(2, &Map.put(&1, :status, :running))
     end)}
  end

  def handle_info({:order_flow, :line_matched, payload}, socket) do
    {:noreply,
     update(socket, :active_lines, fn lines ->
       lines ++ [payload]
     end)}
  end

  def handle_info({:order_flow, :order_created, %{order_id: order_id}}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       Enum.map(stages, &Map.put(&1, :status, :done))
     end)
     |> assign(:orders, OrderFlow.list_orders())
     |> put_flash(:info, "Order ##{order_id} created.")}
  end

  def handle_info({:order_flow, :client_unresolved, %{reason: reason}}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       List.update_at(stages, 1, &Map.put(&1, :status, :failed))
     end)
     |> put_flash(:error, "Client unresolved: #{reason}")}
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
          <li :for={msg <- @messages} class={[
            "text-sm border-l-2 pl-3",
            @active_message && @active_message.id == msg.id && "border-emerald-400 bg-emerald-50",
            !(@active_message && @active_message.id == msg.id) && "border-zinc-200"
          ]}>
            <p class="font-medium">{msg.client_hint || "(no client hint)"} · <span class="text-zinc-500">{msg.kind}</span></p>
            <p class="text-zinc-700 mt-1">{msg.body}</p>
          </li>
        </ol>
      </section>

      <section class="border rounded p-4">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Pipeline</h2>
        <%= if @active_message do %>
          <p class="text-sm text-zinc-700 mb-3">Processing: <span class="font-mono">{@active_message.scenario}</span></p>
          <ShowcaseWeb.Components.PipelineStages.pipeline_stages stages={@active_stages} />

          <button
            type="button"
            class="mt-4 text-xs text-zinc-500 underline"
            phx-click="toggle_cascade_detail"
          >
            {if @cascade_detail_open, do: "Hide", else: "Show"} cascade detail
          </button>

          <%= if @cascade_detail_open and @active_lines != [] do %>
            <div class="mt-3 space-y-2">
              <div :for={line <- @active_lines} class="rounded border border-zinc-200 p-2 text-sm">
                <p class="font-mono">{line.description}</p>
                <p class="text-xs text-zinc-500 mt-1">
                  step: <span class="font-mono">{line.step}</span>
                  · conf: {if line.confidence, do: Float.round(line.confidence, 2), else: "—"}
                  · matched: {line.matched}
                </p>
              </div>
            </div>
          <% end %>
        <% else %>
          <p class="text-sm text-zinc-500">Click "Generate order" to start.</p>
        <% end %>

        <%= if @orders != [] do %>
          <div class="mt-6">
            <h3 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Recent orders</h3>
            <ol class="space-y-2">
              <li :for={order <- Enum.take(@orders, 5)} class="text-sm">
                <a class="underline" href={"/order-flow/orders/#{order.id}"}>
                  Order #{order.id} · {order.client && order.client.name} · {length(order.lines)} line(s)
                </a>
              </li>
            </ol>
          </div>
        <% end %>
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
