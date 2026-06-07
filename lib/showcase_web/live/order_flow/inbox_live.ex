defmodule ShowcaseWeb.OrderFlow.InboxLive do
  use ShowcaseWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Impl.{AliasPromotion, Normalize}
  alias Showcase.OrderFlow.Schemas.{Client, OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  @max_attachments 5
  # 32 MB — Anthropic accepts PDFs up to that size per document.
  @max_attachment_bytes 32_000_000

  @impl true
  def mount(_params, _session, socket) do
    # Mock registration moved to Application.start (REVIEW.md MED-03) — no
    # need to re-register per-mount.
    {:ok,
     socket
     |> assign(:page_title, "OrderFlow")
     |> assign(:messages, OrderFlow.list_messages())
     |> assign(:message_status, OrderFlow.order_status_by_message())
     |> assign(:active_message, nil)
     |> assign(:active_order, nil)
     |> assign(:active_stages, initial_stages())
     |> assign(:active_lines, [])
     |> assign(:analyzing?, false)
     |> assign(:cascade_detail_open, false)
     |> assign(:compose_open, false)
     |> assign(:compose_form, empty_compose_form())
     # Right-pane view toggles between :pipeline (default — stages + cascade
     # detail) and :order (full order detail with line corrections, client
     # picker, Send to ERP). Switched via "Open order" / "Back to pipeline".
     |> assign(:right_pane_view, :pipeline)
     |> assign(:products, Repo.all(from p in Product, order_by: p.name))
     |> assign(:clients, Repo.all(from c in Client, order_by: c.name))
     |> allow_upload(:attachments,
       accept: ~w(.jpg .jpeg .png .gif .webp .pdf),
       max_entries: @max_attachments,
       max_file_size: @max_attachment_bytes
     )}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Inbox navigation
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_message", %{"id" => id}, socket) do
    msg = OrderFlow.get_message!(String.to_integer(id))
    order = OrderFlow.order_for_message(msg.id)
    cascade_lines = OrderFlow.cascade_events_for_order(order)

    {:noreply,
     socket
     |> assign(:active_message, msg)
     |> assign(:active_order, order)
     |> assign(:active_stages, stages_for(order))
     |> assign(:active_lines, cascade_lines)
     |> assign(:analyzing?, false)
     |> assign(:right_pane_view, :pipeline)}
  end

  def handle_event("show_order_detail", _, socket) do
    {:noreply, assign(socket, :right_pane_view, :order)}
  end

  def handle_event("show_pipeline", _, socket) do
    {:noreply, assign(socket, :right_pane_view, :pipeline)}
  end

  def handle_event("assign_client", %{"client_id" => client_id}, socket) when client_id != "" do
    order = socket.assigns.active_order
    client = Repo.get!(Client, String.to_integer(client_id))

    {:ok, updated} =
      order
      |> Showcase.OrderFlow.Schemas.Order.changeset(%{client_id: client.id, status: "pending_review"})
      |> Repo.update()

    {:noreply,
     socket
     |> assign(:active_order, OrderFlow.find_order(updated.id))
     |> assign(:message_status, OrderFlow.order_status_by_message())
     |> put_flash(:info, "Assigned to #{client.name}.")}
  end

  def handle_event("assign_client", _, socket), do: {:noreply, socket}

  def handle_event("correct_line", %{"line_id" => line_id, "product_id" => product_id}, socket)
      when product_id != "" do
    line = Repo.get!(OrderLine, String.to_integer(line_id))
    product = Repo.get!(Product, String.to_integer(product_id))
    order = socket.assigns.active_order

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

      maybe_promote_to_global(normalized, product.id, now)
    end)

    refreshed = OrderFlow.find_order(order.id)

    {:noreply,
     socket
     |> assign(:active_order, refreshed)
     |> assign(:active_lines, OrderFlow.cascade_events_for_order(refreshed))
     |> put_flash(:info, "Corrected. Next time this client sends the same text, no LLM needed.")}
  end

  def handle_event("correct_line", _, socket), do: {:noreply, socket}

  def handle_event("add_to_catalog", %{"line_id" => line_id}, socket) do
    line = Repo.get!(OrderLine, String.to_integer(line_id))

    case OrderFlow.create_product_for_line(line) do
      {:ok, %{product: product}} ->
        order = socket.assigns.active_order
        refreshed = OrderFlow.find_order(order.id)

        {:noreply,
         socket
         |> assign(:active_order, refreshed)
         |> assign(:active_lines, OrderFlow.cascade_events_for_order(refreshed))
         |> assign(:products, Repo.all(from p in Product, order_by: p.name))
         |> put_flash(
           :info,
           "Added \"#{product.name}\" to the catalog as #{product.sku}. Future orders auto-match."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add to catalog: #{inspect(reason)}")}
    end
  end

  defp maybe_promote_to_global(normalized_text, product_id, now) do
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
      existing_global = OrderFlow.find_global_alias(normalized_text, product_id)

      unless existing_global do
        avg_confidence =
          entries |> Enum.map(& &1.confidence) |> then(fn xs -> Enum.sum(xs) / length(xs) end)

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

  def handle_event("clear_selection", _, socket) do
    {:noreply,
     socket
     |> assign(:active_message, nil)
     |> assign(:active_order, nil)
     |> assign(:active_stages, initial_stages())
     |> assign(:active_lines, [])
     |> assign(:analyzing?, false)}
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    case OrderFlow.delete_message(String.to_integer(id)) do
      {:ok, _} ->
        cleared =
          if socket.assigns.active_message && socket.assigns.active_message.id == String.to_integer(id) do
            socket
            |> assign(:active_message, nil)
            |> assign(:active_order, nil)
            |> assign(:active_stages, initial_stages())
            |> assign(:active_lines, [])
          else
            socket
          end

        {:noreply,
         cleared
         |> assign(:messages, OrderFlow.list_messages())
         |> assign(:message_status, OrderFlow.order_status_by_message())
         |> put_flash(:info, "Message deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete message.")}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Analyze flow
  # ──────────────────────────────────────────────────────────────────────────

  def handle_event("analyze_message", %{"id" => id}, socket) do
    msg_id = String.to_integer(id)

    case OrderFlow.enqueue_analysis(msg_id) do
      {:ok, _job, msg} ->
        topic = "order_flow:processing:#{msg.id}"
        Phoenix.PubSub.subscribe(Showcase.PubSub, topic)

        {:noreply,
         socket
         |> assign(:active_message, msg)
         |> assign(:active_order, nil)
         |> assign(:analyzing?, true)
         |> assign(:active_stages, [
           %{label: "Extract", status: :running},
           %{label: "Identify client", status: :pending},
           %{label: "Match lines", status: :pending},
           %{label: "Create order", status: :pending}
         ])
         |> assign(:active_lines, [])}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enqueue: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle_cascade_detail", _params, socket) do
    {:noreply, update(socket, :cascade_detail_open, &(!&1))}
  end

  def handle_event("send_to_erp", _, socket) do
    case socket.assigns.active_order do
      nil ->
        {:noreply, socket}

      order ->
        case OrderFlow.mark_sent_to_erp(order) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:active_order, updated)
             |> assign(:message_status, OrderFlow.order_status_by_message())
             |> put_flash(:info, "Order ##{updated.id} sent to NeuroniERP as #{OrderFlow.erp_reference(updated)}.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not send to ERP.")}
        end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Compose modal
  # ──────────────────────────────────────────────────────────────────────────

  def handle_event("open_compose", _, socket) do
    {:noreply,
     socket
     |> assign(:compose_open, true)
     |> assign(:compose_form, empty_compose_form())}
  end

  def handle_event("close_compose", _, socket) do
    {:noreply, assign(socket, :compose_open, false)}
  end

  def handle_event("validate_compose", %{"compose" => attrs}, socket) do
    {:noreply, assign(socket, :compose_form, Map.merge(empty_compose_form(), attrs))}
  end

  def handle_event("cancel_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("send_compose", %{"compose" => attrs}, socket) do
    saved_paths =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        url = OrderFlow.save_attachment(path, entry.client_name)
        {:ok, url}
      end)

    payload = %{
      from_address: Map.get(attrs, "from_address"),
      subject: Map.get(attrs, "subject"),
      body: Map.get(attrs, "body"),
      attachment_paths: saved_paths
    }

    case OrderFlow.create_composed_message(payload) do
      {:ok, msg} ->
        messages = OrderFlow.list_messages()

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:active_message, msg)
         |> assign(:active_order, nil)
         |> assign(:active_stages, initial_stages())
         |> assign(:active_lines, [])
         |> assign(:compose_open, false)
         |> assign(:compose_form, empty_compose_form())
         |> put_flash(:info, "Email landed in the inbox. Click Analyze to extract the order.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:compose_form, Map.merge(empty_compose_form(), attrs))
         |> put_flash(:error, "Could not send: #{format_errors(cs)}")}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # PubSub — pipeline progress
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:order_flow, :extracted, payload}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       stages
       |> List.update_at(0, &Map.put(&1, :status, :done))
       |> List.update_at(1, &Map.put(&1, :status, :running))
     end)
     |> put_flash(:info, "Extracted #{payload.line_count} line(s); hint: #{payload.client_hint}")}
  end

  def handle_info({:order_flow, :client_identified, _payload}, socket) do
    {:noreply,
     update(socket, :active_stages, fn stages ->
       stages
       |> List.update_at(1, &Map.put(&1, :status, :done))
       |> List.update_at(2, &Map.put(&1, :status, :running))
     end)}
  end

  def handle_info({:order_flow, :line_matched, payload}, socket) do
    {:noreply, update(socket, :active_lines, fn lines -> lines ++ [payload] end)}
  end

  def handle_info({:order_flow, :order_created, %{order_id: order_id}}, socket) do
    order = OrderFlow.find_order(order_id)

    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       Enum.map(stages, fn stage ->
         # Preserve :needs_review marks (e.g. client unresolved); advance
         # everything else to :done.
         if stage.status == :needs_review, do: stage, else: Map.put(stage, :status, :done)
       end)
     end)
     |> assign(:analyzing?, false)
     |> assign(:active_order, order)
     |> assign(:messages, OrderFlow.list_messages())
     |> assign(:message_status, OrderFlow.order_status_by_message())
     |> put_flash(:info, "Order ##{order_id} created.")}
  end

  def handle_info({:order_flow, :client_unresolved, %{reason: reason}}, socket) do
    # Pipeline continues — we just flag stage 2 as "needs review" and let
    # subsequent stages advance.
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       stages
       |> List.update_at(1, &Map.put(&1, :status, :needs_review))
       |> List.update_at(2, &Map.put(&1, :status, :running))
     end)
     |> put_flash(:info, "Client not auto-identified (#{reason}) — you'll pick it on the order page.")}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Render
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-[1600px] mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Dashboard
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-[1600px] mx-auto px-6 py-6 flex items-end justify-between gap-6">
          <div>
            <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
              Neurony · OrderFlow
            </p>
            <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
              Customer emails → structured orders
            </h1>
            <p class="mt-2 font-body text-sm text-ink/60">
              Real Claude pipeline against synthetic emails. Compose a new order, watch the cascade match products.
            </p>
          </div>

          <button
            type="button"
            phx-click="open_compose"
            class="rounded-xl bg-purple px-5 py-2.5 text-sm font-semibold text-white hover:opacity-90 shadow-sm flex items-center gap-2"
          >
            <.pencil_icon /> Write an email
          </button>
        </div>
      </div>

      <%= if msg = @flash["info"] do %>
        <div class="max-w-[1600px] mx-auto px-6 pt-4">
          <div class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
            {msg}
          </div>
        </div>
      <% end %>
      <%= if msg = @flash["error"] do %>
        <div class="max-w-[1600px] mx-auto px-6 pt-4">
          <div class="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">
            {msg}
          </div>
        </div>
      <% end %>

      <!-- Three-pane layout -->
      <div class="max-w-[1600px] mx-auto px-6 py-6 grid grid-cols-12 gap-4">

        <!-- LEFT: Inbox list -->
        <section class="col-span-3 rounded-2xl border border-line bg-white shadow-sm overflow-hidden flex flex-col" style="height: calc(100vh - 240px); min-height: 500px;">
          <header class="px-4 py-3 border-b border-line flex items-center justify-between">
            <h2 class="font-heading text-base font-bold text-ink">Inbox</h2>
            <span class="text-xs text-ink/50">{length(@messages)} messages</span>
          </header>

          <ol class="overflow-y-auto flex-1 divide-y divide-line">
            <li :for={msg <- @messages} class="group relative">
              <button
                type="button"
                phx-click="select_message"
                phx-value-id={msg.id}
                class={[
                  "w-full text-left px-4 py-3 hover:bg-surface-lav transition-colors",
                  @active_message && @active_message.id == msg.id && "bg-surface-lav-2 border-l-4 border-l-purple"
                ]}
              >
                <div class="flex items-start justify-between gap-2 mb-1">
                  <p class="text-sm font-semibold text-ink truncate">
                    {display_from(msg)}
                  </p>
                  <span :if={msg.composed and not Map.has_key?(@message_status, msg.id)} class="shrink-0 rounded-full bg-purple/10 text-purple text-[10px] font-bold uppercase tracking-wider px-2 py-0.5">
                    new
                  </span>
                </div>
                <p class="text-xs font-medium text-ink/80 truncate pr-6">
                  {display_subject(msg)}
                </p>
                <p class="text-xs text-ink/50 truncate mt-1 pr-6">
                  {display_body_preview(msg)}
                </p>
                <div class="flex items-center flex-wrap gap-1.5 mt-2">
                  <%= for {label, classes} <- row_badges(msg, @message_status) do %>
                    <span class={["text-[10px] font-bold uppercase tracking-wider rounded px-1.5 py-0.5", classes]}>
                      {label}
                    </span>
                  <% end %>
                  <span :if={(msg.attachment_paths || []) != []} class="inline-flex items-center gap-1 text-[10px] text-ink/60">
                    <.paperclip_icon /> {length(msg.attachment_paths)}
                  </span>
                  <span :if={msg.kind == "whatsapp"} class="text-[10px] text-emerald-700 bg-emerald-50 rounded px-1.5 py-0.5">WhatsApp</span>
                </div>
              </button>

              <!-- Hover-only trash icon (Gmail-style row delete) -->
              <button
                type="button"
                phx-click="delete_message"
                phx-value-id={msg.id}
                data-confirm="Delete this message and its order?"
                class="absolute top-3 right-2 opacity-0 group-hover:opacity-100 transition-opacity rounded-md bg-white border border-line p-1.5 text-ink/50 hover:text-rose-600 hover:border-rose-300 shadow-sm"
                title="Delete message"
              >
                <.trash_icon />
              </button>
            </li>

            <li :if={@messages == []} class="px-4 py-8 text-center text-sm text-ink/50">
              No messages yet. Click <span class="font-semibold">Write an email</span> to compose one.
            </li>
          </ol>
        </section>

        <!-- MIDDLE: Reader -->
        <section class="col-span-5 rounded-2xl border border-line bg-white shadow-sm overflow-hidden flex flex-col" style="height: calc(100vh - 240px); min-height: 500px;">
          <%= if @active_message do %>
            <header class="px-6 py-4 border-b border-line">
              <div class="flex items-start justify-between gap-4">
                <div class="flex-1">
                  <h2 class="font-heading text-xl font-bold text-ink leading-snug">
                    {display_subject(@active_message)}
                  </h2>
                  <div class="mt-2 flex items-center gap-3 text-xs text-ink/60">
                    <span class="font-mono">From: <span class="text-ink/80">{display_from(@active_message)}</span></span>
                    <span class="text-ink/30">·</span>
                    <span>{Calendar.strftime(@active_message.inserted_at, "%b %d · %H:%M")}</span>
                  </div>
                </div>

                <button
                  type="button"
                  phx-click="delete_message"
                  phx-value-id={@active_message.id}
                  data-confirm="Delete this message?"
                  class="text-xs text-ink/50 hover:text-rose-600"
                  title="Delete"
                >
                  <.trash_icon />
                </button>
              </div>
            </header>

            <div class="flex-1 overflow-y-auto px-6 py-5 space-y-5">
              <%= if (@active_message.body || "") |> String.trim() != "" do %>
                <article class="prose prose-sm max-w-none whitespace-pre-wrap text-ink leading-relaxed">
                  {@active_message.body}
                </article>
              <% else %>
                <p class="text-sm text-ink/50 italic">
                  (no body — see attachment{if length(@active_message.attachment_paths || []) > 1, do: "s", else: ""} below)
                </p>
              <% end %>

              <div :if={(@active_message.attachment_paths || []) != []} class="border-t border-line pt-5">
                <p class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-3">
                  Attachments ({length(@active_message.attachment_paths)})
                </p>
                <div class="grid grid-cols-2 gap-3">
                  <a
                    :for={path <- @active_message.attachment_paths}
                    href={path}
                    target="_blank"
                    class="block rounded-xl border border-line overflow-hidden hover:border-purple transition-colors"
                  >
                    <%= if pdf?(path) do %>
                      <div class="flex flex-col items-center justify-center h-40 bg-surface-lav-2 p-4 gap-2">
                        <.document_icon class="w-10 h-10 text-rose-600" />
                        <p class="text-xs font-semibold text-ink truncate w-full text-center">
                          {Path.basename(path)}
                        </p>
                        <p class="text-[10px] text-ink/50 uppercase tracking-wider">PDF</p>
                      </div>
                    <% else %>
                      <img src={path} class="w-full h-40 object-cover" alt="attachment" />
                    <% end %>
                  </a>
                </div>
              </div>
            </div>

            <footer class="px-6 py-4 border-t border-line bg-surface-lav-2/50 flex items-center justify-between gap-3">
              <div class="text-xs text-ink/60">
                <%= if @active_order do %>
                  <span class="inline-flex items-center gap-1 text-emerald-700">
                    <.check_circle_icon /> Already processed — Order #{@active_order.id}
                  </span>
                <% else %>
                  <%= if @analyzing? do %>
                    <span class="inline-flex items-center gap-1 text-purple">
                      <.spinner /> Analyzing…
                    </span>
                  <% else %>
                    <span>Ready to extract.</span>
                  <% end %>
                <% end %>
              </div>

              <div class="flex items-center gap-2">
                <button
                  :if={@active_order}
                  type="button"
                  phx-click="show_order_detail"
                  class="rounded-lg border border-line bg-white px-4 py-2 text-sm font-medium text-ink hover:bg-surface-lav"
                >
                  Open order
                </button>
                <button
                  type="button"
                  phx-click="analyze_message"
                  phx-value-id={@active_message.id}
                  disabled={@analyzing?}
                  class={[
                    "rounded-lg px-5 py-2 text-sm font-semibold shadow-sm",
                    @analyzing? && "bg-ink/20 text-ink/50 cursor-not-allowed",
                    !@analyzing? && "bg-purple text-white hover:opacity-90"
                  ]}
                >
                  {if @active_order, do: "Re-analyze", else: "Analyze"}
                </button>
              </div>
            </footer>
          <% else %>
            <div class="flex-1 flex items-center justify-center px-6 text-center">
              <div class="max-w-sm">
                <.envelope_icon class="w-12 h-12 mx-auto text-ink/20" />
                <p class="mt-4 font-heading text-lg font-semibold text-ink">No message selected</p>
                <p class="mt-1 text-sm text-ink/60">
                  Pick an email from the inbox to read it. Or click <span class="font-semibold">Write an email</span> in the header to compose a new one.
                </p>
              </div>
            </div>
          <% end %>
        </section>

        <!-- RIGHT: Pipeline (default) ↔ Order detail (when "Open order" clicked) -->
        <section class="col-span-4 rounded-2xl border border-line bg-white shadow-sm overflow-hidden flex flex-col" style="height: calc(100vh - 240px); min-height: 500px;">
          <%= cond do %>
            <% @right_pane_view == :order and @active_order -> %>
              <!-- ─── ORDER DETAIL VIEW ─── -->
              <header class="px-5 py-3 border-b border-line flex items-center justify-between gap-3">
                <button type="button" phx-click="show_pipeline"
                  class="flex items-center gap-1 text-xs text-ink/60 hover:text-purple">
                  ← Pipeline
                </button>
                <div class="text-right">
                  <h2 class="font-heading text-base font-bold text-ink leading-none">
                    Order #{@active_order.id}
                  </h2>
                  <p class="text-xs text-ink/50 mt-1 truncate max-w-[200px]">
                    {(@active_order.client && @active_order.client.name) || "client not assigned"}
                  </p>
                </div>
              </header>

              <div class="flex-1 overflow-y-auto px-5 py-4 space-y-3">
                <%= if @active_order.status == "sent_to_erp" do %>
                  <div class="rounded-lg border border-emerald-300 bg-emerald-50 p-3">
                    <p class="text-sm font-semibold text-emerald-900">✓ Sent to NeuroniERP</p>
                    <p class="text-xs text-emerald-800 mt-1 font-mono">{OrderFlow.erp_reference(@active_order)}</p>
                    <a href="#" class="inline-block mt-1 text-xs text-emerald-700 underline">view in ERP →</a>
                  </div>
                <% end %>

                <%= if is_nil(@active_order.client_id) do %>
                  <div class="rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-2">
                    <p class="text-xs font-bold uppercase tracking-wider text-amber-900">Client not auto-identified</p>
                    <p class="text-xs text-amber-900/80">
                      Pick a client — corrections will write client-scoped aliases.
                    </p>
                    <form phx-change="assign_client">
                      <select name="client_id" class="w-full rounded-md border border-amber-300 bg-white px-2 py-1.5 text-xs">
                        <option value="">Pick a client…</option>
                        <option :for={c <- @clients} value={c.id}>{c.name}</option>
                      </select>
                    </form>
                  </div>
                <% end %>

                <div class="space-y-2">
                  <p class="text-xs font-bold uppercase tracking-wider text-ink/50">
                    Lines ({length(@active_order.lines)})
                  </p>

                  <div :for={line <- @active_order.lines} class={[
                    "rounded-lg border p-3 space-y-2",
                    line.product_id && "border-emerald-200 bg-emerald-50/40",
                    !line.product_id && "border-amber-300 bg-amber-50/40"
                  ]}>
                    <div class="flex items-start justify-between gap-2">
                      <p class="font-mono text-xs text-ink break-words flex-1">{line.raw_description}</p>
                      <span class="text-xs font-semibold text-ink/70 shrink-0">×{line.quantity}</span>
                    </div>

                    <div class="flex items-center justify-between gap-2 text-[11px]">
                      <span class={[
                        "rounded px-1.5 py-0.5 font-mono",
                        line.product_id && "bg-emerald-100 text-emerald-800",
                        !line.product_id && "bg-amber-100 text-amber-800"
                      ]}>
                        {(line.product && line.product.sku) || "no match"}
                      </span>
                      <span class="text-ink/50 font-mono">
                        {line.match_step || "—"}
                        <span :if={line.confidence}> · {Float.round(line.confidence, 2)}</span>
                      </span>
                    </div>

                    <form phx-change="correct_line">
                      <input type="hidden" name="line_id" value={line.id} />
                      <select name="product_id" class="w-full rounded-md border border-line bg-white px-2 py-1 text-xs">
                        <option value="">Correct match…</option>
                        <option :for={p <- @products} value={p.id} selected={line.product_id == p.id}>
                          {p.name} ({p.sku})
                        </option>
                      </select>
                    </form>

                    <%= if is_nil(line.product_id) do %>
                      <button
                        type="button"
                        phx-click="add_to_catalog"
                        phx-value-line_id={line.id}
                        data-confirm={"Add \"#{line.raw_description}\" to the catalog as a new product?"}
                        class="w-full rounded-md border border-purple/30 bg-white px-2 py-1.5 text-xs font-semibold text-purple hover:bg-purple/5 inline-flex items-center justify-center gap-1"
                      >
                        + Add to catalog
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>

              <footer class="px-5 py-3 border-t border-line bg-surface-lav-2/50 space-y-2">
                <%= if @active_order.status == "sent_to_erp" do %>
                  <span class="block w-full text-center rounded-lg bg-emerald-100 text-emerald-900 px-4 py-2 text-sm font-semibold">
                    ✓ Sent
                  </span>
                <% else %>
                  <% unmatched = Enum.count(@active_order.lines, &is_nil(&1.product_id)) %>
                  <%= if unmatched > 0 do %>
                    <div class="rounded-md border border-amber-300 bg-amber-50 px-2.5 py-1.5 text-[11px] text-amber-900">
                      <span class="font-semibold">{unmatched} line(s) still unmatched</span> — they'll be sent to the ERP tagged <span class="font-mono">NEEDS_REVIEW</span> for a human to resolve.
                    </div>
                  <% end %>

                  <button type="button" phx-click="send_to_erp" disabled={is_nil(@active_order.client_id)}
                    class={[
                      "w-full rounded-lg px-4 py-2 text-sm font-semibold shadow-sm",
                      is_nil(@active_order.client_id) && "bg-ink/20 text-ink/50 cursor-not-allowed",
                      !is_nil(@active_order.client_id) && "bg-purple text-white hover:opacity-90"
                    ]}>
                    Send to ERP
                  </button>
                  <p :if={is_nil(@active_order.client_id)} class="text-[10px] text-amber-700 text-center">
                    Assign a client first.
                  </p>
                <% end %>
              </footer>

            <% @active_message -> %>
              <!-- ─── PIPELINE VIEW (default) ─── -->
              <header class="px-5 py-3 border-b border-line">
                <h2 class="font-heading text-base font-bold text-ink">Pipeline</h2>
                <p class="text-xs text-ink/50 mt-0.5">Extract → identify → cascade → create</p>
              </header>

              <div class="flex-1 overflow-y-auto px-5 py-4 space-y-4">
                <ol class="space-y-2">
                  <li :for={stage <- @active_stages} class={[
                    "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm border",
                    stage.status == :pending && "bg-zinc-50 text-ink/50 border-line",
                    stage.status == :running && "bg-purple/10 text-purple border-purple/30 animate-pulse font-semibold",
                    stage.status == :done && "bg-emerald-50 text-emerald-900 border-emerald-200",
                    stage.status == :needs_review && "bg-amber-50 text-amber-900 border-amber-300",
                    stage.status == :failed && "bg-rose-50 text-rose-900 border-rose-200"
                  ]}>
                    <span class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold shrink-0" style={stage_marker_style(stage.status)}>
                      {stage_marker(stage.status)}
                    </span>
                    <span class="flex-1">{stage.label}</span>
                    <span :if={stage.status == :needs_review} class="text-[10px] uppercase tracking-wider font-bold">needs review</span>
                  </li>
                </ol>

                <button
                  type="button"
                  class="text-xs text-ink/60 underline hover:text-purple"
                  phx-click="toggle_cascade_detail"
                >
                  {if @cascade_detail_open, do: "Hide", else: "Show"} cascade detail
                </button>

                <%= if @cascade_detail_open do %>
                  <div class="space-y-2 pt-2 border-t border-line">
                    <p class="text-xs font-bold uppercase tracking-wider text-ink/50">Per-line matches</p>
                    <%= if @active_lines == [] do %>
                      <p class="text-xs text-ink/50 italic">
                        No lines matched yet. Run Analyze to populate.
                      </p>
                    <% else %>
                      <div :for={line <- @active_lines} class={[
                        "rounded-lg border p-3 text-sm",
                        line.matched && "border-emerald-200 bg-emerald-50",
                        !line.matched && "border-amber-300 bg-amber-50"
                      ]}>
                        <p class="font-mono text-ink">{line.description}</p>
                        <p class="text-xs text-ink/60 mt-1">
                          <span class="font-mono">{line.step || "—"}</span>
                          <span class="text-ink/30">·</span>
                          conf {if line.confidence, do: Float.round(line.confidence, 2), else: "—"}
                          <span class="text-ink/30">·</span>
                          {if line.matched, do: "matched", else: "no match"}
                        </p>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @active_order do %>
                  <div class="pt-3 border-t border-line space-y-2">
                    <p class="text-xs font-bold uppercase tracking-wider text-ink/50">Order created</p>
                    <button type="button" phx-click="show_order_detail"
                      class="block w-full text-left rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm hover:border-emerald-400">
                      <p class="font-semibold text-emerald-900">
                        Order #{@active_order.id} · {(@active_order.client && @active_order.client.name) || "client not assigned"}
                      </p>
                      <p class="text-xs text-emerald-800 mt-1">
                        {length(@active_order.lines)} line(s) — click to review →
                      </p>
                    </button>
                  </div>
                <% end %>
              </div>

            <% true -> %>
              <!-- ─── EMPTY STATE ─── -->
              <header class="px-5 py-3 border-b border-line">
                <h2 class="font-heading text-base font-bold text-ink">Pipeline</h2>
                <p class="text-xs text-ink/50 mt-0.5">Extract → identify → cascade → create</p>
              </header>
              <div class="flex-1 flex items-center justify-center px-5 text-center">
                <p class="text-sm text-ink/50">
                  Pick a message and click <span class="font-semibold">Analyze</span> to start the pipeline.
                </p>
              </div>
          <% end %>
        </section>
      </div>

      <!-- Compose modal (Gmail bottom-right slider) -->
      <%= if @compose_open do %>
        <div class="fixed bottom-0 right-6 z-40 w-[520px] max-h-[85vh] rounded-t-2xl border border-line border-b-0 bg-white shadow-2xl flex flex-col">
          <header class="bg-ink text-white px-5 py-3 rounded-t-2xl flex items-center justify-between">
            <p class="font-heading text-sm font-bold">New email</p>
            <button type="button" phx-click="close_compose" class="text-white/80 hover:text-white text-xl leading-none">×</button>
          </header>

          <form
            phx-change="validate_compose"
            phx-submit="send_compose"
            class="flex-1 overflow-y-auto"
          >
            <div class="px-5 py-3 border-b border-line">
              <label class="block text-[10px] uppercase tracking-wider text-ink/50 mb-1">From</label>
              <input
                type="text"
                name="compose[from_address]"
                value={@compose_form["from_address"] || ""}
                placeholder="orders@orderflow.com"
                class="w-full text-sm bg-transparent focus:outline-none text-ink"
              />
            </div>

            <div class="px-5 py-3 border-b border-line">
              <label class="block text-[10px] uppercase tracking-wider text-ink/50 mb-1">Subject</label>
              <input
                type="text"
                name="compose[subject]"
                value={@compose_form["subject"] || ""}
                placeholder="Subject"
                class="w-full text-sm bg-transparent focus:outline-none text-ink"
              />
            </div>

            <div class="px-5 py-3">
              <textarea
                name="compose[body]"
                placeholder="Write your order…"
                rows="8"
                class="w-full text-sm bg-transparent focus:outline-none text-ink resize-none"
              >{@compose_form["body"] || ""}</textarea>
            </div>

            <!-- Attachment uploads -->
            <div class="px-5 py-3 border-t border-line">
              <div class="flex items-center justify-between mb-2">
                <p class="text-[10px] uppercase tracking-wider text-ink/50">Attachments</p>
                <label class="inline-flex items-center gap-1 text-xs text-purple cursor-pointer hover:opacity-80">
                  <.paperclip_icon /> Add file (image or PDF)
                  <.live_file_input upload={@uploads.attachments} class="hidden" />
                </label>
              </div>

              <div :if={@uploads.attachments.entries != []} class="space-y-2">
                <div :for={entry <- @uploads.attachments.entries} class="flex items-center gap-2 text-xs bg-surface-lav-2 rounded-lg px-3 py-2">
                  <%= if pdf_entry?(entry) do %>
                    <div class="w-12 h-12 rounded bg-rose-50 border border-rose-200 flex items-center justify-center shrink-0">
                      <.document_icon class="w-6 h-6 text-rose-600" />
                    </div>
                  <% else %>
                    <.live_img_preview entry={entry} class="w-12 h-12 object-cover rounded" />
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <p class="truncate text-ink">{entry.client_name}</p>
                    <div class="h-1 bg-line rounded-full mt-1 overflow-hidden">
                      <div class="h-full bg-purple transition-all" style={"width: #{entry.progress}%"}></div>
                    </div>
                  </div>
                  <button type="button" phx-click="cancel_attachment" phx-value-ref={entry.ref} class="text-ink/50 hover:text-rose-600">×</button>
                </div>

                <div :for={err <- upload_errors(@uploads.attachments)} class="text-xs text-rose-600">
                  {error_to_string(err)}
                </div>
              </div>
            </div>

            <footer class="px-5 py-3 border-t border-line bg-surface-lav-2 flex items-center justify-between">
              <p class="text-[10px] text-ink/50">Composed emails hit real Claude.</p>
              <button
                type="submit"
                class="rounded-lg bg-purple px-5 py-2 text-sm font-semibold text-white hover:opacity-90 shadow-sm"
              >
                Send
              </button>
            </footer>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Inline icon components
  # ──────────────────────────────────────────────────────────────────────────

  defp pencil_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z"/>
    </svg>
    """
  end

  defp paperclip_icon(assigns) do
    ~H"""
    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M18.375 12.739l-7.693 7.693a4.5 4.5 0 01-6.364-6.364l10.94-10.94A3 3 0 1119.5 7.372L8.552 18.32m.009-.01l-.01.01m5.699-9.941l-7.81 7.81a1.5 1.5 0 002.122 2.122l7.81-7.81"/>
    </svg>
    """
  end

  defp trash_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"/>
    </svg>
    """
  end

  defp document_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "w-5 h-5" end)

    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/>
    </svg>
    """
  end

  defp envelope_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "w-5 h-5" end)

    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75"/>
    </svg>
    """
  end

  defp check_circle_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
    </svg>
    """
  end

  defp spinner(assigns) do
    ~H"""
    <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"/>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v3a5 5 0 00-5 5H4z"/>
    </svg>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp initial_stages do
    [
      %{label: "Extract", status: :pending},
      %{label: "Identify client", status: :pending},
      %{label: "Match lines", status: :pending},
      %{label: "Create order", status: :pending}
    ]
  end

  defp stages_for(nil), do: initial_stages()

  defp stages_for(_order) do
    Enum.map(initial_stages(), &Map.put(&1, :status, :done))
  end

  defp stage_marker(:pending), do: "·"
  defp stage_marker(:running), do: "…"
  defp stage_marker(:done), do: "✓"
  defp stage_marker(:needs_review), do: "?"
  defp stage_marker(:failed), do: "!"

  defp stage_marker_style(:pending), do: "background:#e4e4e7;color:#71717a"
  defp stage_marker_style(:running), do: "background:#a78bfa33;color:#7c3aed"
  defp stage_marker_style(:done), do: "background:#a7f3d0;color:#065f46"
  defp stage_marker_style(:needs_review), do: "background:#fde68a;color:#92400e"
  defp stage_marker_style(:failed), do: "background:#fecaca;color:#9f1239"

  defp empty_compose_form do
    %{"from_address" => "", "subject" => "", "body" => ""}
  end

  defp display_from(%{from_address: from}) when is_binary(from) and from != "", do: from
  defp display_from(%{client_hint: hint}) when is_binary(hint) and hint != "", do: hint
  defp display_from(_), do: "(unknown sender)"

  defp display_subject(%{subject: subj}) when is_binary(subj) and subj != "", do: subj

  defp display_subject(%{body: body}) when is_binary(body) and body != "" do
    String.slice(body, 0, 60)
  end

  defp display_subject(%{attachment_paths: paths}) when is_list(paths) and paths != [] do
    "(attachment only — #{length(paths)} file#{if length(paths) > 1, do: "s", else: ""})"
  end

  defp display_subject(_), do: "(no subject)"

  defp display_body_preview(%{body: body}) when is_binary(body) and body != "", do: body

  defp display_body_preview(%{attachment_paths: paths}) when is_list(paths) and paths != [] do
    "📎 #{length(paths)} attachment#{if length(paths) > 1, do: "s", else: ""}"
  end

  defp display_body_preview(_), do: "(no preview)"

  # Returns a list of `{label, tw_classes}` tuples — the badges that should
  # render on the inbox row for a given message.
  defp row_badges(msg, message_status) do
    case Map.get(message_status, msg.id) do
      nil ->
        # Not yet analyzed.
        [{"Pending", "bg-ink/10 text-ink/60"}]

      %{order_status: "sent_to_erp"} ->
        [{"Sent ✓", "bg-purple text-white"}]

      %{order_status: "needs_client"} ->
        [{"Needs client", "bg-amber-100 text-amber-800"}]

      %{matched: matched, total: total} when total > 0 and matched == total ->
        [{"Matched #{matched}/#{total}", "bg-emerald-100 text-emerald-800"}]

      %{matched: matched, total: total} when total > 0 ->
        [{"Partial #{matched}/#{total}", "bg-amber-100 text-amber-800"}]

      _ ->
        [{"Analyzed", "bg-emerald-100 text-emerald-800"}]
    end
  end

  defp pdf?(path) when is_binary(path),
    do: String.downcase(Path.extname(path)) == ".pdf"

  defp pdf?(_), do: false

  defp pdf_entry?(%Phoenix.LiveView.UploadEntry{client_name: name, client_type: type}) do
    String.downcase(Path.extname(name || "")) == ".pdf" or type == "application/pdf"
  end

  defp pdf_entry?(_), do: false

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  defp error_to_string(:too_large), do: "File too large (max 32 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max #{@max_attachments})"
  defp error_to_string(:not_accepted), do: "File type not accepted (jpg/png/gif/webp/pdf only)"
  defp error_to_string(other), do: to_string(other)
end
