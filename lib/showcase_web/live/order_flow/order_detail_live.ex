defmodule ShowcaseWeb.OrderFlow.OrderDetailLive do
  use ShowcaseWeb, :live_view

  import Ecto.Query

  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Impl.{AliasPromotion, Normalize}
  alias Showcase.OrderFlow.Schemas.{OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = OrderFlow.find_order(String.to_integer(id))

    {:ok,
     socket
     |> assign(:page_title, "Order ##{order.id}")
     |> assign(:order, order)
     |> assign(:products, Repo.all(from p in Product, order_by: p.name))}
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
            Order · {@order.client && @order.client.name}
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            Order #{@order.id}
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            Status <span class="font-mono">{@order.status}</span> · {length(@order.lines)} line(s)
          </p>
        </div>
      </div>

    <div class="max-w-5xl mx-auto p-6">
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
    </div>
    </div>
    """
  end
end
