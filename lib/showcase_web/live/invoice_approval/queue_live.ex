defmodule ShowcaseWeb.InvoiceApproval.QueueLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval

  @max_invoice_size 32_000_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and
         Application.get_env(:showcase, :anthropic_client_impl) ==
           Showcase.Common.AnthropicClient.Mock do
      InvoiceApproval.register_mock_responses()
    end

    {:ok,
     socket
     |> assign(:page_title, "Invoice Approval")
     |> assign(:bundles, InvoiceApproval.list_bundles())
     |> assign(:clients, InvoiceApproval.list_clients())
     |> assign(:compose_open, false)
     |> assign(:compose_form, empty_compose_form())
     |> allow_upload(:invoice_pdf,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: @max_invoice_size
     )}
  end

  # ── Compose modal ─────────────────────────────────────────────────────

  @impl true
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

  def handle_event("cancel_invoice", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :invoice_pdf, ref)}
  end

  def handle_event("send_compose", %{"compose" => attrs}, socket) do
    invoice_path =
      consume_uploaded_entries(socket, :invoice_pdf, fn %{path: path}, entry ->
        url = InvoiceApproval.save_attachment(path, entry.client_name)
        {:ok, url}
      end)
      |> List.first()

    payload = %{
      from_email: Map.get(attrs, "from_email", "") |> String.trim(),
      subject: Map.get(attrs, "subject"),
      body: Map.get(attrs, "body"),
      invoice_path: invoice_path
    }

    case InvoiceApproval.create_bundle_from_invoice(payload) do
      {:ok, bundle} ->
        {:noreply,
         socket
         |> assign(:bundles, InvoiceApproval.list_bundles())
         |> assign(:compose_open, false)
         |> assign(:compose_form, empty_compose_form())
         |> push_navigate(to: "/invoice-approval/bundles/#{bundle.id}")}

      {:error, {:unknown_client, email}} ->
        {:noreply,
         socket
         |> assign(:compose_form, Map.merge(empty_compose_form(), attrs))
         |> put_flash(:error, "No client found for #{email}. Pick from the list below.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create bundle: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_bundle", %{"id" => id}, socket) do
    case InvoiceApproval.delete_bundle(String.to_integer(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:bundles, InvoiceApproval.list_bundles())
         |> put_flash(:info, "Bundle deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete bundle.")}
    end
  end

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Dashboard
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-6 flex items-end justify-between gap-6">
          <div>
            <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
              Neurony · Invoice Approval
            </p>
            <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
              Three-way invoice matching
            </h1>
            <p class="mt-2 font-body text-sm text-ink/60">
              Contract on file. Aviz de însoțire on delivery. Factura by email. AI reconciles all three and scopes the AP clerk to genuinely ambiguous cases.
            </p>
          </div>

          <button
            type="button"
            phx-click="open_compose"
            class="rounded-xl bg-purple px-5 py-2.5 text-sm font-semibold text-white hover:opacity-90 shadow-sm flex items-center gap-2 shrink-0"
          >
            <.envelope_icon /> Receive an invoice
          </button>
        </div>
      </div>

      <%= if msg = @flash["info"] do %>
        <div class="max-w-6xl mx-auto px-6 pt-4">
          <div class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
            {msg}
          </div>
        </div>
      <% end %>
      <%= if msg = @flash["error"] do %>
        <div class="max-w-6xl mx-auto px-6 pt-4">
          <div class="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">
            {msg}
          </div>
        </div>
      <% end %>

      <main class="max-w-6xl mx-auto px-6 py-8">
        <div class="rounded-2xl border border-line bg-white shadow-sm overflow-hidden">
          <header class="px-6 py-3 border-b border-line flex items-center justify-between bg-surface-lav-2/30">
            <h2 class="font-heading text-base font-bold text-ink">Invoice queue</h2>
            <p class="text-xs text-ink/50">{length(@bundles)} bundle(s)</p>
          </header>

          <div :if={@bundles == []} class="px-6 py-12 text-center text-sm text-ink/50">
            No invoices yet. Click <span class="font-semibold">Receive an invoice</span> to simulate one arriving.
          </div>

          <ul class="divide-y divide-line">
            <li :for={bundle <- @bundles} class="group relative hover:bg-surface-lav/50 transition-colors">
              <a href={"/invoice-approval/bundles/#{bundle.id}"} class="block px-6 py-4">
                <div class="flex items-center justify-between gap-4">
                  <div class="flex items-center gap-4 flex-1 min-w-0">
                    <!-- Client avatar -->
                    <div class="w-10 h-10 rounded-full bg-purple/10 text-purple flex items-center justify-center font-bold text-sm shrink-0">
                      {client_initials(bundle.client)}
                    </div>

                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2">
                        <p class="font-semibold text-ink truncate">{bundle.client.name}</p>
                        <span class="text-xs text-ink/40">·</span>
                        <p class="text-xs text-ink/60 font-mono truncate">
                          {bundle.invoice["invoice_number"] || "F-?"}
                        </p>
                      </div>
                      <p class="text-xs text-ink/60 truncate mt-0.5">
                        {bundle.contract && bundle.contract.name || "(no contract)"} · {format_total(bundle.invoice)}
                      </p>
                    </div>
                  </div>

                  <div class="flex items-center gap-3 shrink-0">
                    <% {label, classes} = status_badge(bundle.status) %>
                    <span class={["text-[10px] font-bold uppercase tracking-wider rounded-full px-3 py-1", classes]}>
                      {label}
                    </span>
                    <span class="text-xs text-ink/30">→</span>
                  </div>
                </div>
              </a>

              <button
                type="button"
                phx-click="delete_bundle"
                phx-value-id={bundle.id}
                data-confirm="Delete this bundle and its verdict history?"
                class="absolute top-3 right-3 opacity-0 group-hover:opacity-100 transition-opacity rounded-md bg-white border border-line p-1.5 text-ink/50 hover:text-rose-600 hover:border-rose-300 shadow-sm"
                title="Delete bundle"
              >
                <.trash_icon />
              </button>
            </li>
          </ul>
        </div>
      </main>

      <!-- Compose modal (Gmail-style bottom-right slider) -->
      <%= if @compose_open do %>
        <div class="fixed bottom-0 right-6 z-40 w-[520px] max-h-[85vh] rounded-t-2xl border border-line border-b-0 bg-white shadow-2xl flex flex-col">
          <header class="bg-ink text-white px-5 py-3 rounded-t-2xl flex items-center justify-between">
            <p class="font-heading text-sm font-bold">Receive an invoice</p>
            <button type="button" phx-click="close_compose" class="text-white/80 hover:text-white text-xl leading-none">×</button>
          </header>

          <form phx-change="validate_compose" phx-submit="send_compose" class="flex-1 overflow-y-auto">
            <div class="px-5 py-3 border-b border-line">
              <label class="block text-[10px] uppercase tracking-wider text-ink/50 mb-1">From (sender)</label>
              <select
                name="compose[from_email]"
                class="w-full text-sm bg-transparent focus:outline-none text-ink"
              >
                <option value="">Pick a client…</option>
                <option :for={c <- @clients} value={c.email} selected={@compose_form["from_email"] == c.email}>
                  {c.name} &lt;{c.email}&gt;
                </option>
              </select>
              <p class="text-[10px] text-ink/50 mt-1">
                Matching the sender to a client lets the system auto-pull their contract.
              </p>
            </div>

            <div class="px-5 py-3 border-b border-line">
              <label class="block text-[10px] uppercase tracking-wider text-ink/50 mb-1">Subject</label>
              <input
                type="text"
                name="compose[subject]"
                value={@compose_form["subject"] || ""}
                placeholder="F-2026-1234"
                class="w-full text-sm bg-transparent focus:outline-none text-ink"
              />
            </div>

            <div class="px-5 py-3">
              <textarea
                name="compose[body]"
                placeholder="Optional message body…"
                rows="3"
                class="w-full text-sm bg-transparent focus:outline-none text-ink resize-none"
              >{@compose_form["body"] || ""}</textarea>
            </div>

            <!-- Invoice PDF upload -->
            <div class="px-5 py-3 border-t border-line">
              <div class="flex items-center justify-between mb-2">
                <p class="text-[10px] uppercase tracking-wider text-ink/50">Invoice attachment</p>
                <label class="inline-flex items-center gap-1 text-xs text-purple cursor-pointer hover:opacity-80">
                  <.paperclip_icon /> Attach PDF
                  <.live_file_input upload={@uploads.invoice_pdf} class="hidden" />
                </label>
              </div>

              <div :if={@uploads.invoice_pdf.entries != []} class="space-y-2">
                <div :for={entry <- @uploads.invoice_pdf.entries} class="flex items-center gap-2 text-xs bg-surface-lav-2 rounded-lg px-3 py-2">
                  <div class="w-12 h-12 rounded bg-rose-50 border border-rose-200 flex items-center justify-center shrink-0">
                    <.document_icon class="w-6 h-6 text-rose-600" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="truncate text-ink">{entry.client_name}</p>
                    <div class="h-1 bg-line rounded-full mt-1 overflow-hidden">
                      <div class="h-full bg-purple transition-all" style={"width: #{entry.progress}%"}></div>
                    </div>
                  </div>
                  <button type="button" phx-click="cancel_invoice" phx-value-ref={entry.ref} class="text-ink/50 hover:text-rose-600">×</button>
                </div>

                <div :for={err <- upload_errors(@uploads.invoice_pdf)} class="text-xs text-rose-600">
                  {error_to_string(err)}
                </div>
              </div>
            </div>

            <footer class="px-5 py-3 border-t border-line bg-surface-lav-2 flex items-center justify-between">
              <p class="text-[10px] text-ink/50">Pulls the client's contract automatically.</p>
              <button type="submit" class="rounded-lg bg-purple px-5 py-2 text-sm font-semibold text-white hover:opacity-90 shadow-sm">
                Send
              </button>
            </footer>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Icons ─────────────────────────────────────────────────────────────

  defp envelope_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75"/>
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

  defp document_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "w-5 h-5" end)

    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/>
    </svg>
    """
  end

  defp trash_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166M5.79 5.79c.34-.059.68-.114 1.022-.165m12.418.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79"/>
    </svg>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp empty_compose_form do
    %{"from_email" => "", "subject" => "", "body" => ""}
  end

  defp client_initials(%{name: name}) when is_binary(name) do
    name
    |> String.split(~r/\s+/)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join("")
    |> String.upcase()
  end

  defp client_initials(_), do: "?"

  defp format_total(%{"total" => total}) when is_number(total) do
    "Total: #{:io_lib.format("~.2f", [total * 1.0]) |> List.to_string()} RON"
  end

  defp format_total(_), do: ""

  defp status_badge("pending"),     do: {"Pending", "bg-ink/10 text-ink/60"}
  defp status_badge("needs_aviz"),  do: {"Needs aviz", "bg-amber-100 text-amber-800"}
  defp status_badge("analyzing"),   do: {"Analyzing…", "bg-purple/10 text-purple"}
  defp status_badge("approve"),     do: {"Approved", "bg-emerald-100 text-emerald-800"}
  defp status_badge("reject"),      do: {"Rejected", "bg-rose-100 text-rose-800"}
  defp status_badge("needs_human"), do: {"Needs human", "bg-amber-100 text-amber-800"}
  defp status_badge("sent_to_erp"), do: {"Sent to ERP ✓", "bg-purple text-white"}
  defp status_badge(_),             do: {"—", "bg-ink/10 text-ink/60"}

  defp error_to_string(:too_large), do: "File too large (max 32 MB)"
  defp error_to_string(:too_many_files), do: "Only one invoice attachment per email"
  defp error_to_string(:not_accepted), do: "PDF / JPG / PNG only"
  defp error_to_string(other), do: to_string(other)
end
