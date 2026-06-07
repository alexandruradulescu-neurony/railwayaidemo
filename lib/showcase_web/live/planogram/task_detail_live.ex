defmodule ShowcaseWeb.Planogram.TaskDetailLive do
  @moduledoc """
  Detail view for a single VerificationTask.

  Renders one of four panels by `task.status`:

    * `pending`   — empty state + Run analysis button
    * `analyzing` — "Calling Claude vision API…" banner
    * `failed`    — rose banner with `task.error_reason`
    * `complete`  — compliance gauge, executive summary, per-row table,
                    issues, suggestions, JSON inspector, cost badge.
                    Includes the partial-salvage banner when
                    `task.result["_partial"]` is true.
  """
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.Impl.ResultRenderer
  alias Showcase.Common.AnthropicClient.Types.Usage

  alias ShowcaseWeb.Components.{CostBadge, JSONInspector}
  alias ShowcaseWeb.Planogram.Components.{ComplianceGauge, PerRowTable}

  import CostBadge, only: [cost_badge: 1]
  import JSONInspector, only: [json_inspector: 1]
  import ComplianceGauge
  import PerRowTable

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Planogram.get_task!(String.to_integer(id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Showcase.PubSub, Showcase.Planogram.VisionPipeline.topic(task.id))
    end

    socket =
      socket
      |> allow_upload(:shelf,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 1,
        max_file_size: 8_000_000
      )
      |> assign_task(task)

    {:ok, socket}
  end

  defp assign_task(socket, task) do
    rendered = if task.result, do: ResultRenderer.render(task.result), else: nil
    usage = if task.usage, do: usage_struct(task.usage), else: nil

    socket
    |> assign(:task, task)
    |> assign(:rendered, rendered)
    |> assign(:usage, usage)
  end

  defp usage_struct(%{"input_tokens" => i, "output_tokens" => o, "cost_estimate_cents" => c}) do
    %Usage{input_tokens: i, output_tokens: o, cost_estimate_cents: c * 1.0}
  end

  defp usage_struct(_), do: nil

  @impl true
  def handle_event("run_analysis", _, socket) do
    Planogram.enqueue_analysis(socket.assigns.task.id)
    {:noreply, put_flash(socket, :info, "Analysis enqueued.")}
  end

  def handle_event("validate_shelf", _params, socket), do: {:noreply, socket}

  def handle_event("upload_shelf", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :shelf, fn %{path: tmp}, _entry ->
        {:ok, File.read!(tmp)}
      end)

    case uploaded do
      [bytes] ->
        case Planogram.save_shelf_photo(socket.assigns.task, bytes) do
          {:ok, updated} ->
            updated = Planogram.get_task!(updated.id)

            {:noreply,
             socket
             |> put_flash(:info, "Shelf photo uploaded.")
             |> assign_task(updated)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not save shelf photo.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No photo received.")}
    end
  end

  @impl true
  def handle_info({:planogram, :task_failed, _task_id, _reason}, socket) do
    {:noreply, assign_task(socket, Planogram.get_task!(socket.assigns.task.id))}
  end

  def handle_info({:planogram, _phase, _task_id}, socket) do
    {:noreply, assign_task(socket, Planogram.get_task!(socket.assigns.task.id))}
  end

  @impl true
  def render(assigns) do
    main_width =
      case assigns.task.status do
        "complete" -> "max-w-7xl"
        _ -> "max-w-5xl"
      end

    assigns = assign(assigns, :main_width, main_width)

    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class={["mx-auto px-6 py-5 flex items-center justify-between", @main_width]}>
          <div>
            <h1 class="text-xl font-semibold"><%= @task.store_name %></h1>
            <p class="text-sm text-zinc-500 mt-1">
              <%= @task.planogram.name %> · due <%= @task.due_date %> ·
              <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
                <%= @task.status %>
              </span>
            </p>
          </div>
          <a href="/planogram" class="text-sm text-zinc-500 underline">&larr; Back</a>
        </div>
      </header>

      <main class={["mx-auto px-6 py-6 space-y-6", @main_width]}>
        <%= case @task.status do %>
          <% s when s in ["pending"] -> %>
            <.pending_panel task={@task} uploads={@uploads} />

          <% "analyzing" -> %>
            <div class="rounded border bg-blue-50 px-4 py-3 text-sm text-blue-800">
              Calling Claude vision API…
            </div>

          <% "failed" -> %>
            <div class="rounded border bg-rose-50 px-4 py-3 text-sm text-rose-800">
              Analysis failed: <%= @task.error_reason %>
            </div>

          <% "complete" -> %>
            <.result_panel rendered={@rendered} usage={@usage} raw={@task.result} task={@task} />
        <% end %>
      </main>
    </div>
    """
  end

  attr :task, :map, required: true
  attr :uploads, :map, required: true

  defp pending_panel(assigns) do
    ~H"""
    <section class="rounded border bg-white p-5 space-y-4">
      <h2 class="text-lg font-medium">Reference planogram</h2>
      <img
        :if={@task.planogram.reference_image_path}
        src={@task.planogram.reference_image_path}
        alt={@task.planogram.name}
        class="w-full max-h-72 object-contain rounded border bg-zinc-50"
      />
      <p class="text-xs text-zinc-500">{@task.planogram.description}</p>
    </section>

    <section :if={@task.photo_path} class="rounded border bg-white p-5 space-y-3">
      <h2 class="text-lg font-medium">Shelf photo</h2>
      <img
        src={@task.photo_path}
        alt="Captured shelf"
        class="w-full max-h-72 object-contain rounded border bg-zinc-50"
      />
    </section>

    <section :if={!@task.photo_path} class="rounded border bg-white p-5 space-y-3">
      <h2 class="text-lg font-medium">Upload shelf photo</h2>
      <p class="text-sm text-zinc-500">
        Pick a photo from your computer, or use the
        <a class="underline" href={"/planogram/mobile/#{@task.mobile_token}"}>mobile capture link</a>.
      </p>

      <form phx-submit="upload_shelf" phx-change="validate_shelf" class="space-y-3">
        <.live_file_input upload={@uploads.shelf} class="block w-full text-sm" />
        <div
          :for={entry <- @uploads.shelf.entries}
          class="text-xs text-zinc-600"
        >
          {entry.client_name} — {entry.progress}%
          <div
            :for={err <- upload_errors(@uploads.shelf, entry)}
            class="text-rose-600"
          >
            {upload_error_to_string(err)}
          </div>
        </div>
        <button
          type="submit"
          disabled={@uploads.shelf.entries == []}
          class="rounded bg-neurony-600 px-3 py-2 text-sm font-medium text-white hover:bg-neurony-700 disabled:opacity-40"
        >
          Upload photo
        </button>
      </form>
    </section>

    <div class="flex items-center gap-3">
      <button
        phx-click="run_analysis"
        class="rounded bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700"
      >
        Run analysis
      </button>
      <span :if={!@task.photo_path} class="text-xs text-zinc-500">
        No photo uploaded — the bundled <code class="font-mono">{@task.scenario}</code>
        scenario will be used.
      </span>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "Photo too large (max 8 MB)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported file (.png, .jpg)."
  defp upload_error_to_string(:too_many_files), do: "One file at a time."
  defp upload_error_to_string(_), do: "Upload error."

  attr :rendered, :map, required: true
  attr :usage, :any, required: true
  attr :raw, :map, required: true
  attr :task, :map, required: true

  defp result_panel(assigns) do
    max_row =
      assigns.rendered.rows
      |> Enum.map(& &1.position)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> 3
        list -> Enum.max(list)
      end

    assigns = assign(assigns, :max_row, max_row)

    ~H"""
    <div :if={@rendered.partial?} class="rounded border border-amber-300 bg-amber-50 px-4 py-2 text-xs text-amber-800">
      The AI response was truncated. Showing salvaged fields via ResilientJSONParser.
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- Left/main column: shelf photo with overlay tags --%>
      <section class="rounded border bg-white p-5 lg:col-span-2">
        <h2 class="text-lg font-medium mb-3">Shelf compliance</h2>
        <div class="relative rounded overflow-hidden bg-zinc-100">
          <img
            :if={@task.photo_path}
            src={@task.photo_path}
            alt="Audited shelf"
            class="w-full h-auto block"
          />
          <div
            :if={!@task.photo_path}
            class="aspect-[4/3] flex items-center justify-center text-sm text-zinc-400"
          >
            (no photo — bundled scenario was used)
          </div>

          <%!-- Overlay tags for issues + extracted prices --%>
          <span
            :for={iss <- @rendered.issues}
            class={[
              "absolute -translate-x-1/2 -translate-y-1/2",
              "rounded px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
              "shadow-md whitespace-nowrap",
              issue_badge_classes(iss.type)
            ]}
            style={overlay_style(iss.row, iss.horizontal_position, @max_row)}
            title={iss.description}
          >
            {iss.badge}
          </span>

          <span
            :for={price <- @rendered.extracted_prices}
            class={[
              "absolute -translate-x-1/2 -translate-y-1/2",
              "rounded bg-blue-600 text-white px-2 py-0.5 text-[10px] font-semibold",
              "shadow-md whitespace-nowrap"
            ]}
            style={overlay_style(price.row, price.horizontal_position, @max_row)}
          >
            {price.text} ✓
          </span>
        </div>

        <p class="text-sm text-zinc-700 mt-4">{@rendered.executive_summary}</p>
      </section>

      <%!-- Right column: stats sidebar --%>
      <section class="space-y-4">
        <div class="rounded border bg-white p-5 text-center">
          <div class="text-xs uppercase tracking-wide text-zinc-500 mb-2">
            Compliance Score
          </div>
          <.compliance_gauge pct={@rendered.gauge_pct} />
        </div>

        <div class="rounded border bg-white p-4 flex items-center gap-3">
          <span class="rounded-full bg-rose-100 text-rose-600 p-2">
            <.icon name="hero-x-circle" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-zinc-500">Mismatches Found</div>
            <div class="text-2xl font-semibold">{@rendered.mismatches_count}</div>
          </div>
        </div>

        <div class="rounded border bg-white p-4 flex items-center gap-3">
          <span class="rounded-full bg-blue-100 text-blue-600 p-2">
            <.icon name="hero-currency-dollar" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-zinc-500">Price Tags Verified</div>
            <div class="text-2xl font-semibold">{@rendered.prices_count}</div>
          </div>
        </div>

        <div :if={@rendered.out_of_stock_count > 0} class="rounded border bg-white p-4 flex items-center gap-3">
          <span class="rounded-full bg-amber-100 text-amber-600 p-2">
            <.icon name="hero-exclamation-triangle" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-zinc-500">Out of Stock</div>
            <div class="text-2xl font-semibold">{@rendered.out_of_stock_count}</div>
          </div>
        </div>

        <div class="rounded border bg-emerald-50 border-emerald-200 px-4 py-3 flex items-center gap-2 text-sm text-emerald-800">
          <.icon name="hero-check-circle" class="size-5" />
          <span class="font-medium">AI Analysis: Complete</span>
        </div>

        <div class="flex items-center gap-2 px-1">
          <.cost_badge :if={@usage} usage={@usage} />
          <span class="text-xs text-zinc-400">
            photo quality: {@rendered.photo_quality.score || "?"}
          </span>
        </div>
      </section>
    </div>

    <section :if={@rendered.rows != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Per-row breakdown</h2>
      <.per_row_table rows={@rendered.rows} />
    </section>

    <section :if={@rendered.issues != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Issues ({length(@rendered.issues)})</h2>
      <ul class="space-y-3">
        <li :for={iss <- @rendered.issues} class="flex gap-3 items-start">
          <span class={[
            "rounded px-2 py-0.5 text-xs uppercase tracking-wide",
            severity_badge_classes(iss.severity_color)
          ]}>
            {iss.severity}
          </span>
          <div class="flex-1">
            <div class="font-medium">{iss.type}</div>
            <div class="text-sm text-zinc-700">{iss.description}</div>
            <div class="text-xs text-zinc-500 mt-1">Impact: {iss.business_impact}</div>
          </div>
        </li>
      </ul>
    </section>

    <section :if={@rendered.suggestions != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Suggested actions</h2>
      <ul class="list-disc list-inside text-sm text-zinc-700 space-y-1">
        <li :for={s <- @rendered.suggestions}>{s}</li>
      </ul>
    </section>

    <.json_inspector data={@raw} />
    """
  end

  # ── Overlay positioning ────────────────────────────────────────────────

  # Given a 1-based row index, a horizontal position keyword, and the max row,
  # produce inline `top`/`left` percentages. Rows are distributed evenly down
  # the photo; horizontal positions left/center/right map to 18/50/82%.
  defp overlay_style(row, horizontal_position, max_row) do
    rows = max(max_row, 1)

    row =
      case row do
        n when is_integer(n) and n >= 1 and n <= rows -> n
        _ -> 1
      end

    top_pct = round((row - 0.5) / rows * 100)

    left_pct =
      case horizontal_position do
        "left" -> 18
        "right" -> 82
        _ -> 50
      end

    "top: #{top_pct}%; left: #{left_pct}%;"
  end

  # Issue badge color classes — literal strings so Tailwind 4 can scan them.
  defp issue_badge_classes("missing_product"), do: "bg-rose-600 text-white"
  defp issue_badge_classes("wrong_placement"), do: "bg-amber-500 text-white"
  defp issue_badge_classes("wrong_qty"), do: "bg-amber-500 text-white"
  defp issue_badge_classes("out_of_stock"), do: "bg-orange-600 text-white"
  defp issue_badge_classes("unauthorized_item"), do: "bg-rose-600 text-white"
  defp issue_badge_classes("photo_quality"), do: "bg-zinc-600 text-white"
  defp issue_badge_classes("mismatch"), do: "bg-rose-600 text-white"
  defp issue_badge_classes(_), do: "bg-zinc-600 text-white"

  # Severity badge classes — literal strings.
  defp severity_badge_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp severity_badge_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp severity_badge_classes("emerald"), do: "bg-emerald-100 text-emerald-700"
  defp severity_badge_classes(_), do: "bg-zinc-100 text-zinc-700"

  defp status_classes("pending"), do: "bg-zinc-100 text-zinc-700"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-zinc-100"
end
