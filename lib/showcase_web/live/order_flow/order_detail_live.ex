defmodule ShowcaseWeb.OrderFlow.OrderDetailLive do
  use ShowcaseWeb, :live_view

  import Ecto.Query

  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Impl.{AliasPromotion, Normalize}
  alias Showcase.OrderFlow.Schemas.{Client, Order, OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = OrderFlow.find_order(String.to_integer(id))

    {:ok,
     socket
     |> assign(:page_title, "Order ##{order.id}")
     |> assign(:order, order)
     |> assign(:products, Repo.all(from p in Product, order_by: p.name))
     |> assign(:clients, Repo.all(from c in Client, order_by: c.name))}
  end

  @impl true
  def handle_event("assign_client", %{"client_id" => client_id}, socket) when client_id != "" do
    order = socket.assigns.order
    client = Repo.get!(Client, String.to_integer(client_id))

    order
    |> Order.changeset(%{client_id: client.id, status: "pending_review"})
    |> Repo.update!()

    {:noreply,
     socket
     |> assign(:order, OrderFlow.find_order(order.id))
     |> put_flash(:info, "Assigned to #{client.name}. Re-run analyze to populate client-scoped aliases.")}
  end

  def handle_event("assign_client", _, socket), do: {:noreply, socket}

  def handle_event("send_to_erp", _, socket) do
    case OrderFlow.mark_sent_to_erp(socket.assigns.order) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:order, updated)
         |> put_flash(:info, "Sent to NeuroniERP as #{OrderFlow.erp_reference(updated)}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not send to ERP.")}
    end
  end

  @impl true
  def handle_event("correct_line", %{"line_id" => line_id, "product_id" => product_id}, socket)
      when product_id != "" do
    line = Repo.get!(OrderLine, to_int(line_id))
    product = Repo.get!(Product, to_int(product_id))
    order = socket.assigns.order

    Repo.transaction(fn ->
      line
      |> OrderLine.changeset(%{product_id: product.id, match_step: "correction", confidence: 0.9})
      |> Repo.update!()

      now = DateTime.utc_now()
      normalized = Normalize.normalize_text(line.raw_description)

      case Repo.get_by(ProductAlias,
             normalized_text: normalized,
             client_id: order.client_id,
             product_id: product.id
           ) do
        nil ->
          %ProductAlias{}
          |> ProductAlias.changeset(%{
            normalized_text: normalized,
            product_id: product.id,
            client_id: order.client_id,
            confidence: 0.9,
            last_used_at: now,
            use_count: 1,
            source: "correction"
          })
          |> Repo.insert!()

        existing ->
          existing
          |> ProductAlias.changeset(%{
            confidence: min(existing.confidence + 0.05, 1.0),
            use_count: existing.use_count + 1,
            last_used_at: now
          })
          |> Repo.update!()
      end

      # After writing/updating the client-scoped alias, check if the
      # (normalized_text → product_id) mapping is now eligible for global
      # promotion (≥2 distinct clients with avg confidence ≥ 0.7).
      maybe_promote_to_global(normalized, product.id, now)
    end)

    {:noreply,
     socket
     |> assign(:order, OrderFlow.find_order(order.id))
     |> put_flash(:info, "Corrected. Future runs on this client will match without the LLM.")}
  end

  # Ignore correction submissions with no product selected (the empty option).
  def handle_event("correct_line", _params, socket), do: {:noreply, socket}

  defp maybe_promote_to_global(normalized_text, product_id, now) do
    # Look at all client-scoped aliases for this (normalized_text, product_id)
    entries =
      Repo.all(
        from a in ProductAlias,
          where:
            a.normalized_text == ^normalized_text and
              a.product_id == ^product_id and
              not is_nil(a.client_id),
          select: %{client_id: a.client_id, confidence: a.confidence}
      )

    if AliasPromotion.eligible_for_global?(entries) do
      # Insert a global alias if one doesn't already exist for this mapping.
      # Note: Ecto refuses `Repo.get_by(..., client_id: nil)` since comparison
      # with nil is unsafe (NULL ≠ NULL in SQL); use `is_nil/1` explicitly.
      existing_global =
        Repo.one(
          from a in ProductAlias,
            where:
              a.normalized_text == ^normalized_text and
                a.product_id == ^product_id and
                is_nil(a.client_id)
        )

      unless existing_global do
        avg_confidence =
          entries
          |> Enum.map(& &1.confidence)
          |> then(fn xs -> Enum.sum(xs) / length(xs) end)

        %ProductAlias{}
        |> ProductAlias.changeset(%{
          normalized_text: normalized_text,
          product_id: product_id,
          client_id: nil,
          confidence: avg_confidence,
          last_used_at: now,
          use_count: length(entries),
          source: "promotion"
        })
        |> Repo.insert!()
      end
    end
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/order-flow" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Inbox
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-5xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Order · {(@order.client && @order.client.name) || "client not assigned"}
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            Order #{@order.id}
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            Status <span class="font-mono">{@order.status}</span> · {length(@order.lines)} line(s)
          </p>
        </div>
      </div>

    <div class="max-w-5xl mx-auto p-6 space-y-4">
      <%= if @order.status == "sent_to_erp" do %>
        <section class="rounded-2xl border border-emerald-200 bg-emerald-50 p-6 shadow-sm">
          <div class="flex items-start gap-4">
            <div class="w-10 h-10 rounded-full bg-emerald-100 text-emerald-700 flex items-center justify-center font-bold text-lg shrink-0">✓</div>
            <div class="flex-1">
              <h2 class="font-heading text-lg font-bold text-emerald-900">
                Order #{@order.id} sent to NeuroniERP
              </h2>
              <p class="text-sm text-emerald-900/80 mt-1">
                Reference <span class="font-mono font-semibold">{OrderFlow.erp_reference(@order)}</span>
                — <a href="#" class="underline hover:text-emerald-700">click here to view in the ERP</a>.
              </p>
            </div>
          </div>
        </section>
      <% end %>

      <section :if={is_nil(@order.client_id)} class="rounded-2xl border border-amber-300 bg-amber-50 p-6 shadow-sm">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center font-bold text-lg shrink-0">?</div>
          <div class="flex-1">
            <h2 class="font-heading text-lg font-bold text-amber-900">Client not auto-identified</h2>
            <p class="text-sm text-amber-900/80 mt-1">
              The extraction couldn't match the sender to a known client. Pick one below — corrections you make afterward will write client-scoped aliases against this choice.
            </p>
            <form phx-change="assign_client" class="mt-4 flex items-center gap-2">
              <label class="text-xs font-bold uppercase tracking-wider text-amber-900">Assign to</label>
              <select name="client_id" class="rounded-lg border border-amber-300 bg-white px-3 py-2 text-sm">
                <option value="">Pick a client…</option>
                <option :for={c <- @clients} value={c.id}>{c.name}</option>
              </select>
            </form>
          </div>
        </div>
      </section>

      <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <table class="w-full text-sm">
        <thead class="text-left text-ink/60 uppercase tracking-wide text-xs">
          <tr>
            <th class="py-2">Raw description</th>
            <th class="py-2">Qty</th>
            <th class="py-2">Matched product</th>
            <th class="py-2">Step</th>
            <th class="py-2">Confidence</th>
            <th class="py-2">Correct</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @order.lines} class="border-t">
            <td class="py-3 font-mono">{line.raw_description}</td>
            <td class="py-3">{line.quantity}</td>
            <td class="py-3">{(line.product && line.product.name) || "—"}</td>
            <td class="py-3 font-mono">{line.match_step || "—"}</td>
            <td class="py-3">{if line.confidence, do: Float.round(line.confidence, 2), else: "—"}</td>
            <td class="py-3">
              <form phx-change="correct_line">
                <input type="hidden" name="line_id" value={line.id} />
                <select name="product_id" class="rounded border border-line px-2 py-1 text-xs">
                  <option value="">Correct…</option>
                  <option :for={p <- @products} value={p.id} selected={line.product_id == p.id}>
                    {p.name} ({p.sku})
                  </option>
                </select>
              </form>
            </td>
          </tr>
        </tbody>
      </table>
      </section>

      <section class="rounded-2xl border border-line bg-white p-6 shadow-sm flex items-center justify-between gap-4">
        <div>
          <h3 class="font-heading text-base font-bold text-ink">Next step</h3>
          <p class="text-sm text-ink/60 mt-1">
            <%= if @order.status == "sent_to_erp" do %>
              Already submitted to NeuroniERP. To re-send, mark it as pending and try again.
            <% else %>
              Push this order into the customer's ERP system to close the loop.
            <% end %>
          </p>
        </div>

        <button
          :if={@order.status != "sent_to_erp"}
          type="button"
          phx-click="send_to_erp"
          disabled={is_nil(@order.client_id)}
          class={[
            "rounded-xl px-5 py-3 text-sm font-semibold shadow-sm flex items-center gap-2",
            is_nil(@order.client_id) && "bg-ink/20 text-ink/50 cursor-not-allowed",
            !is_nil(@order.client_id) && "bg-purple text-white hover:opacity-90"
          ]}
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5"/>
          </svg>
          Send to ERP
        </button>

        <span :if={@order.status == "sent_to_erp"} class="rounded-xl bg-emerald-100 text-emerald-900 px-4 py-2 text-sm font-semibold">
          ✓ Sent
        </span>
      </section>
    </div>
    </div>
    """
  end
end
