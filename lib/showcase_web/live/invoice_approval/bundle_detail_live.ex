defmodule ShowcaseWeb.InvoiceApproval.BundleDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval
  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Schemas.Verdict
  alias Showcase.Repo
  alias ShowcaseWeb.InvoiceApproval.Components.{Documents, MatchingMatrix, ThresholdSliders}

  @max_aviz_size 32_000_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bundle_id = String.to_integer(id)

    case InvoiceApproval.find_bundle(bundle_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/invoice-approval")}

      %{bundle: bundle, verdicts: verdicts} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Showcase.PubSub, "invoice_approval:processing:#{bundle.id}")

          # Auto-enqueue analysis only if the bundle already has both
          # invoice + aviz on hand and no verdict yet (seeded scenarios).
          if verdicts == [] and ready_to_analyze?(bundle) do
            InvoiceApproval.enqueue(bundle.id)
          end
        end

        {:ok,
         socket
         |> assign(:page_title, "Bundle ##{bundle.id}")
         |> assign(:bundle, bundle)
         |> assign(:latest_verdict, List.first(verdicts))
         |> assign(:thresholds, bundle.thresholds)
         |> assign(:active_doc, nil)
         |> assign(:override_reason, "")
         |> allow_upload(:aviz,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: @max_aviz_size,
           auto_upload: true,
           progress: &handle_aviz_progress/3
         )}
    end
  end

  # ── Threshold + verdict events ────────────────────────────────────────

  @impl true
  def handle_event("update_thresholds", params, socket) do
    new_thresholds =
      socket.assigns.thresholds
      |> Map.put("price_pct", to_float(params["price_pct"]))
      |> Map.put("qty_pct", to_float(params["qty_pct"]))
      |> Map.put("date_days", to_int(params["date_days"]))

    re_evaluate_with(socket, new_thresholds)
  end

  def handle_event("override", %{"outcome" => outcome, "reason" => reason}, socket) do
    case InvoiceApproval.override_verdict(socket.assigns.bundle.id, outcome, reason, "admin") do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:latest_verdict, InvoiceApproval.latest_verdict(socket.assigns.bundle.id))
         |> put_flash(:info, "Override recorded.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Override failed: #{inspect(reason)}")}
    end
  end

  # ── Document tile + viewer ────────────────────────────────────────────

  def handle_event("show_doc", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :active_doc, kind)}
  end

  def handle_event("hide_doc", _, socket) do
    {:noreply, assign(socket, :active_doc, nil)}
  end

  # ── Aviz upload (auto-uploads, completion fires the progress callback) ─

  # validate_aviz is wired to phx-change so LiveView accepts the file
  # selection — but the actual "upload done" trigger is the progress
  # callback below (which fires reliably with auto_upload: true).
  def handle_event("validate_aviz", _, socket), do: {:noreply, socket}

  def handle_event("cancel_aviz", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :aviz, ref)}
  end

  # Called by LiveView on each chunk of upload progress. When the entry
  # reaches `done?`, consume it + attach to the bundle + enqueue analysis.
  defp handle_aviz_progress(:aviz, entry, socket) do
    if entry.done? do
      consume_and_attach_aviz(socket)
    else
      {:noreply, socket}
    end
  end

  defp consume_and_attach_aviz(socket) do
    path =
      consume_uploaded_entries(socket, :aviz, fn %{path: temp}, entry ->
        url = InvoiceApproval.save_attachment(temp, entry.client_name)
        {:ok, url}
      end)
      |> List.first()

    case path do
      nil ->
        {:noreply, socket}

      aviz_path ->
        {:ok, updated} = InvoiceApproval.attach_aviz(socket.assigns.bundle.id, aviz_path)

        {:noreply,
         socket
         |> assign(:bundle, updated)
         |> put_flash(:info, "Aviz attached. Analyzing the three documents…")}
    end
  end

  # ── Send to ERP ───────────────────────────────────────────────────────

  def handle_event("send_to_erp", _, socket) do
    case InvoiceApproval.mark_sent_to_erp(socket.assigns.bundle) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:bundle, updated)
         |> put_flash(:info, "Sent to NeuroniERP as #{InvoiceApproval.erp_reference(updated)}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not send to ERP.")}
    end
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:invoice_approval, :verdict_created, %{verdict_id: id}}, socket) do
    verdict = Repo.get!(Verdict, id)
    refreshed = InvoiceApproval.get_bundle!(socket.assigns.bundle.id)

    {:noreply,
     socket
     |> assign(:latest_verdict, verdict)
     |> assign(:bundle, refreshed)}
  end

  def handle_info({:invoice_approval, _event, _payload}, socket), do: {:noreply, socket}

  # ── Threshold re-evaluation (uses existing logic) ─────────────────────

  defp re_evaluate_with(socket, new_thresholds) do
    bundle = socket.assigns.bundle

    case socket.assigns.latest_verdict do
      nil ->
        {:noreply, socket}

      latest ->
        raw_matrix = denormalize(latest.raw_matrix["rows"] || [])

        eval =
          ThresholdEvaluator.evaluate(raw_matrix, %{
            price_pct: new_thresholds["price_pct"],
            qty_pct: new_thresholds["qty_pct"],
            date_days: new_thresholds["date_days"]
          })

        classified_json =
          %{"rows" => Enum.map(eval.classified_matrix, &classified_row_to_json/1)}

        attrs = %{
          bundle_id: bundle.id,
          outcome: Atom.to_string(eval.outcome),
          reasoning: eval.reasoning,
          raw_matrix: latest.raw_matrix,
          classified_matrix: classified_json,
          thresholds_used: new_thresholds,
          source: "ai",
          actor: nil
        }

        {:ok, new_verdict} = %Verdict{} |> Verdict.changeset(attrs) |> Repo.insert()

        {:noreply,
         socket
         |> assign(:thresholds, new_thresholds)
         |> assign(:latest_verdict, new_verdict)}
    end
  end

  defp denormalize(rows) do
    Enum.map(rows, fn r ->
      %{
        line_key: r["line_key"],
        contract: r["contract"] || %{},
        delivery: r["delivery"] || %{},
        invoice: r["invoice"] || %{},
        discrepancies:
          (r["discrepancies"] || [])
          |> Enum.map(fn d ->
            %Showcase.InvoiceApproval.Impl.Types.Discrepancy{
              field: safe_atom(d["field"]),
              contract_value: d["contract_value"],
              delivery_value: d["delivery_value"],
              invoice_value: d["invoice_value"],
              diff_value: as_float(d["diff_value"]),
              diff_basis: safe_atom(d["diff_basis"] || "absolute")
            }
          end)
      }
    end)
  end

  defp safe_atom(nil), do: :unknown
  defp safe_atom(s) when is_binary(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> String.to_atom(s)
    end
  end

  defp as_float(n) when is_number(n), do: n * 1.0
  defp as_float(_), do: 0.0

  defp classified_row_to_json(row) do
    %{
      "line_key" => row.line_key,
      "contract" => row.contract,
      "delivery" => row.delivery,
      "invoice" => row.invoice,
      "discrepancies" =>
        Enum.map(row.discrepancies, fn cd ->
          %{
            "discrepancy" => Map.from_struct(cd.discrepancy),
            "severity" => Atom.to_string(cd.severity),
            "note" => cd.note
          }
        end)
    }
  end

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(v) when is_number(v), do: v * 1.0
  defp to_float(_), do: 0.0

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(_), do: 0

  defp ready_to_analyze?(bundle) do
    invoice_items = get_in(bundle.invoice, ["items"]) || []
    aviz_items = get_in(bundle.delivery_notes, ["items"]) || []
    invoice_items != [] and aviz_items != []
  end

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/invoice-approval" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Queue
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5">
          <div class="flex items-end justify-between gap-4">
            <div>
              <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
                Bundle · {@bundle.client.name}
              </p>
              <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
                Bundle #{@bundle.id}
              </h1>
              <p class="mt-1 font-body text-sm text-ink/60">
                {@bundle.contract && @bundle.contract.name || "(no contract on file)"}
                <span class="text-ink/30 mx-1">·</span>
                Invoice <span class="font-mono">{@bundle.invoice["invoice_number"] || "?"}</span>
              </p>
            </div>
            <% {label, classes} = bundle_status_badge(@bundle.status) %>
            <span class={["text-xs font-bold uppercase tracking-wider rounded-full px-4 py-2", classes]}>
              {label}
            </span>
          </div>
        </div>
      </div>

      <%= if msg = @flash["info"] do %>
        <div class="max-w-7xl mx-auto px-6 pt-4">
          <div class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{msg}</div>
        </div>
      <% end %>
      <%= if msg = @flash["error"] do %>
        <div class="max-w-7xl mx-auto px-6 pt-4">
          <div class="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">{msg}</div>
        </div>
      <% end %>

      <main class="max-w-7xl mx-auto px-6 py-6 space-y-6">
        <!-- 3 document tiles -->
        <section>
          <h2 class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-3">Documents in this bundle</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <.doc_tile
              kind="contract"
              title="Contract"
              subtitle={(@bundle.contract && @bundle.contract.contract_number) || "—"}
              accent="ink"
              present?={not is_nil(@bundle.contract)}
              count={length(get_in(@bundle.contract && @bundle.contract.body, ["line_items"]) || [])}
              upload={false}
            />

            <.doc_tile
              kind="aviz"
              title="Aviz de însoțire"
              subtitle={@bundle.delivery_notes["aviz_number"] || "Not uploaded"}
              accent="amber"
              present?={(@bundle.delivery_notes["items"] || []) != []}
              count={length(@bundle.delivery_notes["items"] || [])}
              upload={(@bundle.delivery_notes["items"] || []) == []}
              uploads={@uploads}
            />

            <.doc_tile
              kind="invoice"
              title="Factură"
              subtitle={@bundle.invoice["invoice_number"] || "—"}
              accent="purple"
              present?={(@bundle.invoice["items"] || []) != []}
              count={length(@bundle.invoice["items"] || [])}
              upload={false}
            />
          </div>
        </section>

        <!-- Inline document viewer (when a tile is clicked) -->
        <%= if @active_doc do %>
          <section class="bg-surface-lav-2/40 rounded-2xl border border-line p-6">
            <header class="flex items-center justify-between mb-4">
              <h3 class="font-heading text-lg font-bold text-ink">
                Document: <span class="capitalize">{@active_doc}</span>
              </h3>
              <button type="button" phx-click="hide_doc" class="text-sm text-ink/60 hover:text-purple">
                Close ×
              </button>
            </header>

            <%= case @active_doc do %>
              <% "contract" -> %>
                <%= if @bundle.contract do %>
                  <Documents.contract_doc contract={@bundle.contract} client={@bundle.client} />
                <% else %>
                  <p class="text-sm text-ink/50">No contract attached to this bundle.</p>
                <% end %>
              <% "aviz" -> %>
                <Documents.aviz_doc delivery_notes={@bundle.delivery_notes} client={@bundle.client} />
              <% "invoice" -> %>
                <Documents.invoice_doc invoice={@bundle.invoice} client={@bundle.client} />
            <% end %>
          </section>
        <% end %>

        <!-- Matrix + Verdict + Thresholds -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Matching matrix -->
          <section class="lg:col-span-2 rounded-2xl border border-line bg-white p-6 shadow-sm">
            <h2 class="font-heading text-base font-bold text-ink mb-3">Matching matrix</h2>
            <%= if @latest_verdict do %>
              <MatchingMatrix.matching_matrix rows={@latest_verdict.classified_matrix["rows"] || []} />
            <% else %>
              <%= cond do %>
                <% @bundle.status == "needs_aviz" -> %>
                  <p class="text-sm text-ink/60">
                    Waiting for the aviz de însoțire to be uploaded. Once attached, the three documents will be reconciled automatically.
                  </p>
                <% @bundle.status == "analyzing" -> %>
                  <p class="text-sm text-purple">Analyzing… please wait.</p>
                <% true -> %>
                  <p class="text-sm text-ink/60">No verdict yet.</p>
              <% end %>
            <% end %>
          </section>

          <!-- Right column -->
          <aside class="space-y-4">
            <!-- Verdict card -->
            <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
              <h2 class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-2">Verdict</h2>
              <%= if @latest_verdict do %>
                <span class={["inline-block text-sm font-bold uppercase tracking-wider rounded-full px-3 py-1", outcome_classes(@latest_verdict.outcome)]}>
                  {String.upcase(@latest_verdict.outcome)}
                </span>
                <p class="mt-2 text-sm text-ink/80">{@latest_verdict.reasoning}</p>
                <p class="mt-2 text-[10px] text-ink/50">source: <span class="font-mono">{@latest_verdict.source}</span></p>
              <% else %>
                <p class="text-sm text-ink/60">Pending.</p>
              <% end %>
            </div>

            <!-- Thresholds -->
            <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
              <h2 class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-3">Thresholds</h2>
              <ThresholdSliders.threshold_sliders thresholds={@thresholds} />
              <p class="text-[10px] text-ink/50 mt-2">Move a slider — the verdict re-evaluates instantly.</p>
            </div>

            <!-- Send to ERP -->
            <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
              <h2 class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-3">Next step</h2>
              <%= if @bundle.status == "sent_to_erp" do %>
                <div class="rounded-lg border border-emerald-300 bg-emerald-50 p-3 text-xs">
                  <p class="font-semibold text-emerald-900">✓ Sent to NeuroniERP</p>
                  <p class="font-mono text-emerald-800 mt-1">{InvoiceApproval.erp_reference(@bundle)}</p>
                  <a href="#" class="text-emerald-700 underline mt-1 inline-block">view in ERP →</a>
                </div>
              <% else %>
                <button
                  type="button"
                  phx-click="send_to_erp"
                  disabled={is_nil(@latest_verdict)}
                  class={[
                    "w-full rounded-lg px-4 py-2 text-sm font-semibold shadow-sm",
                    is_nil(@latest_verdict) && "bg-ink/20 text-ink/50 cursor-not-allowed",
                    !is_nil(@latest_verdict) && "bg-purple text-white hover:opacity-90"
                  ]}
                >
                  Send to ERP
                </button>
                <p :if={is_nil(@latest_verdict)} class="text-[10px] text-ink/50 mt-2 text-center">
                  Get a verdict first.
                </p>
              <% end %>
            </div>

            <!-- Override -->
            <div :if={@latest_verdict} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
              <h2 class="text-xs font-bold uppercase tracking-wider text-ink/50 mb-3">Override verdict</h2>
              <form phx-submit="override" class="space-y-2">
                <select name="outcome" class="w-full rounded-lg border border-line text-sm px-2 py-1.5">
                  <option value="approve">Approve</option>
                  <option value="reject">Reject</option>
                  <option value="needs_human">Needs human</option>
                </select>
                <input type="text" name="reason" placeholder="Reason for override" required
                  class="w-full rounded-lg border border-line text-sm px-2 py-1.5" />
                <button type="submit" class="rounded-lg bg-ink text-white px-3 py-2 text-xs font-medium hover:opacity-90 w-full">
                  Record override
                </button>
              </form>
            </div>
          </aside>
        </div>
      </main>
    </div>
    """
  end

  # ── Function component: the 3 document tiles ──────────────────────────

  attr :kind, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :accent, :string, default: "ink"
  attr :present?, :boolean, default: true
  attr :count, :integer, default: 0
  attr :upload, :boolean, default: false
  attr :uploads, :map, default: nil

  defp doc_tile(assigns) do
    ~H"""
    <%= if @upload and @uploads do %>
      <!-- Upload-zone variant: plain div with drag-drop + auto-trigger
           form. Can't be a <button> (invalid HTML to nest form-in-button). -->
      <div
        phx-drop-target={@uploads.aviz.ref}
        class="rounded-2xl border-2 border-dashed border-amber-300 bg-amber-50/50 p-4"
      >
        <div class="flex items-start gap-3">
          <.tile_icon accent={@accent} />
          <div class="flex-1 min-w-0">
            <p class="font-heading text-sm font-bold text-ink">{@title}</p>
            <p class="text-xs text-ink/60 font-mono truncate mt-0.5">{@subtitle}</p>
            <p class="text-[10px] text-amber-700 font-semibold mt-1">
              Drop a PDF here or click "Choose file" — analysis runs automatically.
            </p>
          </div>
        </div>

        <form phx-change="validate_aviz" class="mt-3">
          <label class="inline-flex items-center gap-1 text-xs text-amber-700 cursor-pointer hover:text-amber-800 font-semibold">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>
            </svg>
            Choose file (PDF)
            <.live_file_input upload={@uploads.aviz} class="hidden" />
          </label>

          <div :if={@uploads.aviz.entries != []} class="mt-2 space-y-1">
            <div :for={entry <- @uploads.aviz.entries} class="flex items-center gap-2 text-xs bg-white border border-amber-300 rounded px-2 py-1">
              <p class="truncate flex-1 text-ink">{entry.client_name}</p>
              <span class="text-amber-700 font-mono">{entry.progress}%</span>
              <button type="button" phx-click="cancel_aviz" phx-value-ref={entry.ref} class="text-ink/50 hover:text-rose-600">×</button>
            </div>
          </div>

          <div :for={err <- upload_errors(@uploads.aviz)} class="text-[10px] text-rose-600 mt-1">
            {error_to_string(err)}
          </div>
        </form>
      </div>
    <% else %>
      <!-- Standard tile: clickable button that opens the doc viewer. -->
      <button
        type="button"
        phx-click={if @present?, do: "show_doc"}
        phx-value-kind={@kind}
        disabled={!@present?}
        class={[
          "block w-full text-left rounded-2xl border-2 p-4 transition-all",
          @present? && "bg-white border-line hover:border-purple cursor-pointer shadow-sm",
          !@present? && "bg-zinc-50 border-zinc-200 opacity-60 cursor-not-allowed"
        ]}
      >
        <div class="flex items-start gap-3">
          <.tile_icon accent={@accent} />
          <div class="flex-1 min-w-0">
            <p class="font-heading text-sm font-bold text-ink">{@title}</p>
            <p class="text-xs text-ink/60 font-mono truncate mt-0.5">{@subtitle}</p>
            <%= if @present? do %>
              <p class="text-[10px] text-ink/50 mt-1">{@count} line item{if @count == 1, do: "", else: "s"} · click to view</p>
            <% else %>
              <p class="text-[10px] text-ink/50 mt-1">Not available</p>
            <% end %>
          </div>
        </div>
      </button>
    <% end %>
    """
  end

  attr :accent, :string, required: true

  defp tile_icon(assigns) do
    ~H"""
    <div class={[
      "w-12 h-14 rounded-md border flex items-center justify-center shrink-0",
      @accent == "ink" && "bg-ink/5 border-ink/20",
      @accent == "amber" && "bg-amber-100 border-amber-300",
      @accent == "purple" && "bg-purple/10 border-purple/30"
    ]}>
      <svg class={[
        "w-7 h-7",
        @accent == "ink" && "text-ink/70",
        @accent == "amber" && "text-amber-700",
        @accent == "purple" && "text-purple"
      ]} fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/>
      </svg>
    </div>
    """
  end

  # ── Styling helpers ───────────────────────────────────────────────────

  defp outcome_classes("approve"),     do: "bg-emerald-100 text-emerald-800"
  defp outcome_classes("reject"),      do: "bg-rose-100 text-rose-800"
  defp outcome_classes("needs_human"), do: "bg-amber-100 text-amber-800"
  defp outcome_classes(_),             do: "bg-ink/10 text-ink/60"

  defp bundle_status_badge("pending"),     do: {"Pending", "bg-ink/10 text-ink/60"}
  defp bundle_status_badge("needs_aviz"),  do: {"Needs aviz", "bg-amber-100 text-amber-800"}
  defp bundle_status_badge("analyzing"),   do: {"Analyzing…", "bg-purple/10 text-purple"}
  defp bundle_status_badge("approve"),     do: {"Approved", "bg-emerald-100 text-emerald-800"}
  defp bundle_status_badge("reject"),      do: {"Rejected", "bg-rose-100 text-rose-800"}
  defp bundle_status_badge("needs_human"), do: {"Needs human", "bg-amber-100 text-amber-800"}
  defp bundle_status_badge("sent_to_erp"), do: {"Sent to ERP ✓", "bg-purple text-white"}
  defp bundle_status_badge(_),             do: {"—", "bg-ink/10 text-ink/60"}

  defp error_to_string(:too_large), do: "Too large (max 32 MB)"
  defp error_to_string(:too_many_files), do: "One file only"
  defp error_to_string(:not_accepted), do: "PDF / JPG / PNG only"
  defp error_to_string(other), do: to_string(other)
end
