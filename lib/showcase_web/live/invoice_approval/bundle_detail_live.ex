defmodule ShowcaseWeb.InvoiceApproval.BundleDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval
  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Schemas.Verdict
  alias Showcase.Repo
  alias ShowcaseWeb.InvoiceApproval.Components.{MatchingMatrix, ThresholdSliders}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bundle_id = String.to_integer(id)

    case InvoiceApproval.find_bundle(bundle_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/invoice-approval")}

      %{bundle: bundle, verdicts: verdicts} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Showcase.PubSub, "invoice_approval:processing:#{bundle.id}")

          if verdicts == [] do
            InvoiceApproval.enqueue(bundle.id)
          end
        end

        {:ok,
         socket
         |> assign(:page_title, "Bundle ##{bundle.id}")
         |> assign(:bundle, bundle)
         |> assign(:latest_verdict, List.first(verdicts))
         |> assign(:thresholds, bundle.thresholds)
         |> assign(:override_reason, "")}
    end
  end

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

  @impl true
  def handle_info({:invoice_approval, :verdict_created, %{verdict_id: id}}, socket) do
    verdict = Repo.get!(Verdict, id)
    {:noreply, assign(socket, :latest_verdict, verdict)}
  end

  def handle_info({:invoice_approval, _event, _payload}, socket), do: {:noreply, socket}

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
              field: String.to_atom(d["field"]),
              contract_value: d["contract_value"],
              delivery_value: d["delivery_value"],
              invoice_value: d["invoice_value"],
              diff_value: d["diff_value"] * 1.0,
              diff_basis: String.to_atom(d["diff_basis"])
            }
          end)
      }
    end)
  end

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

  defp to_float(v) when is_binary(v), do: String.to_float(v)
  defp to_float(v) when is_number(v), do: v * 1.0
  defp to_float(_), do: 0.0

  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(v) when is_integer(v), do: v
  defp to_int(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-xl font-semibold">Bundle #{@bundle.id}</h1>
            <p class="text-sm text-zinc-500 mt-1">
              {@bundle.client.name} · <span class="font-mono">{@bundle.scenario}</span>
            </p>
          </div>
          <a href="/invoice-approval" class="text-sm text-zinc-500 underline">&larr; Queue</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section class="lg:col-span-2 space-y-6">
          <h2 class="text-sm uppercase tracking-wide text-zinc-500">Matching Matrix</h2>
          <%= if @latest_verdict do %>
            <MatchingMatrix.matching_matrix rows={@latest_verdict.classified_matrix["rows"] || []} />
          <% else %>
            <p class="text-sm text-zinc-500">Awaiting AI verdict… (refresh in a few seconds)</p>
          <% end %>
        </section>

        <aside class="space-y-6">
          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Verdict</h2>
            <%= if @latest_verdict do %>
              <p class="text-lg font-semibold">
                <span class={outcome_badge(@latest_verdict.outcome)}>
                  {String.upcase(@latest_verdict.outcome)}
                </span>
              </p>
              <p class="mt-2 text-sm text-zinc-700">{@latest_verdict.reasoning}</p>
              <p class="mt-2 text-xs text-zinc-500">
                source: <span class="font-mono">{@latest_verdict.source}</span>
              </p>
            <% else %>
              <p class="text-sm text-zinc-500">Pending.</p>
            <% end %>
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Thresholds</h2>
            <ThresholdSliders.threshold_sliders thresholds={@thresholds} />
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Override</h2>
            <form phx-submit="override" class="space-y-2">
              <select name="outcome" class="w-full rounded border-zinc-300 text-sm">
                <option value="approve">Approve</option>
                <option value="reject">Reject</option>
                <option value="needs_human">Needs Human</option>
              </select>
              <input
                type="text"
                name="reason"
                placeholder="Reason for override"
                class="w-full rounded border-zinc-300 text-sm"
                required
              />
              <button
                type="submit"
                class="rounded bg-zinc-800 px-3 py-2 text-xs font-medium text-white hover:bg-zinc-900"
              >
                Override verdict
              </button>
            </form>
          </div>
        </aside>
      </main>
    </div>
    """
  end

  defp outcome_badge("approve"),
    do: "inline-block rounded-full bg-emerald-100 px-3 py-1 text-emerald-800 ring-1 ring-emerald-300"

  defp outcome_badge("reject"),
    do: "inline-block rounded-full bg-red-100 px-3 py-1 text-red-900 ring-1 ring-red-300"

  defp outcome_badge("needs_human"),
    do: "inline-block rounded-full bg-amber-100 px-3 py-1 text-amber-900 ring-1 ring-amber-300"

  defp outcome_badge(_),
    do: "inline-block rounded-full bg-zinc-100 px-3 py-1"
end
