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
    usage_source = if task.usage, do: Map.get(task.usage, "source", "live"), else: "live"

    socket
    |> assign(:task, task)
    |> assign(:rendered, rendered)
    |> assign(:usage, usage)
    |> assign(:usage_source, usage_source)
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
            # Auto-enqueue analysis so the AE doesn't need to click twice.
            Planogram.enqueue_analysis(updated.id)

            {:noreply,
             socket
             |> put_flash(:info, "Shelf photo uploaded — analysis running.")
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
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class={["mx-auto px-6 py-5 flex items-center justify-between gap-4", @main_width]}>
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/planogram" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Back to Planogram
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class={["mx-auto px-6 py-6", @main_width]}>
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Audit · {@task.planogram.name}
          </p>
          <div class="mt-2 flex items-baseline gap-3 flex-wrap">
            <h1 class="font-heading font-bold text-3xl text-ink tracking-tight">
              {@task.store_name}
            </h1>
            <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
              {@task.status}
            </span>
          </div>
          <p class="mt-2 font-body text-sm text-ink/60">
            Due {@task.due_date}
          </p>
        </div>
      </div>

      <main class={["mx-auto px-6 py-6 space-y-6", @main_width]}>
        <%= case @task.status do %>
          <% s when s in ["pending"] -> %>
            <.pending_panel task={@task} uploads={@uploads} />

          <% "analyzing" -> %>
            <div class="rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800">
              Calling Claude vision API…
            </div>

          <% "failed" -> %>
            <div class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
              Analysis failed: <%= @task.error_reason %>
            </div>

          <% "complete" -> %>
            <.result_panel rendered={@rendered} usage={@usage} usage_source={@usage_source} raw={@task.result} task={@task} />
        <% end %>
      </main>
    </div>
    """
  end

  attr :task, :map, required: true
  attr :uploads, :map, required: true

  defp pending_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-4">
      <h2 class="text-lg font-medium">Reference planogram</h2>
      <img
        :if={@task.planogram.reference_image_path}
        src={@task.planogram.reference_image_path}
        alt={@task.planogram.name}
        class="w-full max-h-72 object-contain rounded-lg border border-line bg-surface-lav-2"
      />
      <p class="text-xs text-ink/60">{@task.planogram.description}</p>
    </section>

    <section :if={@task.photo_path} class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-3">
      <h2 class="text-lg font-medium">Shelf photo</h2>
      <img
        src={@task.photo_path}
        alt="Captured shelf"
        class="w-full max-h-72 object-contain rounded-lg border border-line bg-surface-lav-2"
      />
    </section>

    <section :if={!@task.photo_path} class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-3">
      <h2 class="text-lg font-medium">Upload shelf photo</h2>
      <p class="text-sm text-ink/60">
        Pick a photo from your computer, or use the
        <a class="underline" href={"/planogram/mobile/#{@task.mobile_token}"}>mobile capture link</a>.
      </p>

      <form phx-submit="upload_shelf" phx-change="validate_shelf" class="space-y-3">
        <.live_file_input upload={@uploads.shelf} class="block w-full text-sm" />
        <div
          :for={entry <- @uploads.shelf.entries}
          class="text-xs text-ink/70"
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
          class="w-full rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Upload & analyze
        </button>
        <p :if={@uploads.shelf.entries == []} class="text-xs text-ink/60">
          Pick a shelf photo to enable the analysis.
        </p>
      </form>
    </section>

    <div :if={@task.photo_path} class="flex items-center gap-3">
      <button
        phx-click="run_analysis"
        class="rounded bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700"
      >
        Re-run analysis
      </button>
      <span class="text-xs text-ink/60">
        Re-runs the AI comparison against the currently-uploaded shelf photo.
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
  attr :usage_source, :string, default: "live"
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
    <div :if={@rendered.partial?} class="rounded-2xl border border-amber-200 bg-amber-50 shadow-sm px-4 py-2 text-xs text-amber-800">
      The AI response was truncated. Showing salvaged fields via ResilientJSONParser.
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- Left/main column: shelf photo with overlay tags --%>
      <section class="rounded-2xl border border-line bg-white p-6 shadow-sm lg:col-span-2">
        <h2 class="text-lg font-medium mb-3">Shelf compliance</h2>
        <div class="relative rounded overflow-hidden bg-surface-lav">
          <img
            :if={photo_on_disk?(@task.photo_path)}
            src={@task.photo_path}
            alt="Audited shelf"
            class="w-full h-auto block"
          />
          <div
            :if={!photo_on_disk?(@task.photo_path)}
            class="aspect-[4/3] flex items-center justify-center text-sm text-ink/50 px-4 text-center"
          >
            <%= if @task.photo_path do %>
              Photo file is no longer on disk ({@task.photo_path}).
              <br />Re-upload the shelf photo to see overlays.
            <% else %>
              (no photo — bundled scenario was used)
            <% end %>
          </div>

          <%!-- Issue overlays: bounding box with label INSIDE at top-left so
               the label always moves with its box, no matter how Claude's
               y-coordinate lands. Falls back to a centered badge when no
               bbox is returned. --%>
          <%= for iss <- @rendered.issues do %>
            <%= if iss.bbox do %>
              <div
                class={[
                  "absolute rounded-md border-2 border-dashed shadow-md overflow-visible",
                  issue_box_classes(iss.type)
                ]}
                style={bbox_style(iss.bbox)}
                title={iss.description}
              >
                <span class={[
                  "absolute top-0 left-0 inline-block",
                  "rounded-tl-md rounded-br-md px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider",
                  "whitespace-nowrap",
                  issue_badge_classes(iss.type)
                ]}>
                  {iss.badge}
                </span>
              </div>
            <% else %>
              <span
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
            <% end %>
          <% end %>

          <%!-- Price overlays: smaller, subtler, anchored INSIDE the bbox so
               they sit on top of the actual price label. --%>
          <%= for price <- dedupe_prices(@rendered.extracted_prices) do %>
            <%= if price.bbox do %>
              <span
                class="absolute rounded bg-blue-600/95 text-white px-1.5 py-0 text-[10px] font-semibold whitespace-nowrap leading-tight shadow"
                style={bbox_label_style(price.bbox)}
                title={price.text}
              >
                {price.text}
              </span>
            <% else %>
              <span
                class="absolute -translate-x-1/2 -translate-y-1/2 rounded bg-blue-600/95 text-white px-1.5 py-0 text-[10px] font-semibold whitespace-nowrap leading-tight shadow"
                style={overlay_style(price.row, price.horizontal_position, @max_row)}
              >
                {price.text}
              </span>
            <% end %>
          <% end %>
        </div>

        <p class="text-sm text-ink/80 mt-4">{@rendered.executive_summary}</p>
      </section>

      <%!-- Right column: stats sidebar --%>
      <section class="space-y-4">
        <div class="rounded-2xl border border-line bg-white p-6 shadow-sm text-center">
          <div class="text-xs uppercase tracking-wide text-ink/60 mb-2">
            Compliance Score
          </div>
          <.compliance_gauge pct={@rendered.gauge_pct} />
        </div>

        <div class="rounded-2xl border border-line bg-white p-6 shadow-sm flex items-center gap-3">
          <span class="rounded-full bg-rose-100 text-rose-600 p-2">
            <.icon name="hero-x-circle" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-ink/60">Mismatches Found</div>
            <div class="text-2xl font-semibold">{@rendered.mismatches_count}</div>
          </div>
        </div>

        <div class="rounded-2xl border border-line bg-white p-6 shadow-sm flex items-center gap-3">
          <span class="rounded-full bg-blue-100 text-blue-600 p-2">
            <.icon name="hero-currency-dollar" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-ink/60">Price Tags Verified</div>
            <div class="text-2xl font-semibold">{@rendered.prices_count}</div>
          </div>
        </div>

        <div :if={@rendered.out_of_stock_count > 0} class="rounded-2xl border border-line bg-white p-6 shadow-sm flex items-center gap-3">
          <span class="rounded-full bg-amber-100 text-amber-600 p-2">
            <.icon name="hero-exclamation-triangle" class="size-5" />
          </span>
          <div class="flex-1">
            <div class="text-xs uppercase tracking-wide text-ink/60">Out of Stock</div>
            <div class="text-2xl font-semibold">{@rendered.out_of_stock_count}</div>
          </div>
        </div>

        <div class="rounded-2xl border border-emerald-200 bg-emerald-50 border-emerald-200 px-4 py-3 flex items-center gap-2 text-sm text-emerald-800">
          <.icon name="hero-check-circle" class="size-5" />
          <span class="font-medium">AI Analysis: Complete</span>
        </div>

        <div class="flex items-center gap-2 px-1">
          <.cost_badge :if={@usage} usage={@usage} source={@usage_source} />
          <span class="text-xs text-ink/50">
            photo quality: {@rendered.photo_quality.score || "?"}
          </span>
        </div>
      </section>
    </div>

    <section :if={@rendered.rows != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Per-row breakdown</h2>
        <p class="text-xs text-ink/60">
          {length(@rendered.rows)} shelf {if length(@rendered.rows) == 1, do: "row", else: "rows"}
        </p>
      </div>

      <div class="space-y-3">
        <div :for={row <- @rendered.rows} class={[
          "rounded-xl border-l-4 bg-surface-lav-2/60 p-4",
          row_card_classes(row.status_color)
        ]}>
          <div class="flex items-baseline justify-between gap-3 flex-wrap">
            <h3 class="font-heading font-semibold text-ink">{row.name}</h3>
            <span class={[
              "rounded-full px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider",
              "bg-#{row.status_color}-100 text-#{row.status_color}-700"
            ]}>
              {row.status}
            </span>
          </div>

          <div :if={row.found_products != []} class="mt-2 flex flex-wrap gap-1.5">
            <span
              :for={p <- row.found_products}
              class="inline-flex items-center gap-1 rounded-md bg-white border border-line px-2 py-0.5 text-xs text-ink/80"
            >
              {p["name"]}
              <span class="text-ink/50">×{p["qty"]}</span>
            </span>
          </div>

          <ul :if={row.issues != []} class="mt-2 space-y-1 text-sm text-ink/70">
            <li :for={iss <- row.issues} class="flex gap-2">
              <span class="text-rose-500">•</span>
              <span>{iss}</span>
            </li>
          </ul>
        </div>
      </div>
    </section>

    <section :if={@rendered.issues != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Issues</h2>
        <span class="rounded-full bg-rose-100 text-rose-700 px-2.5 py-0.5 text-xs font-bold">
          {length(@rendered.issues)} found
        </span>
      </div>

      <ul class="space-y-3">
        <li :for={iss <- @rendered.issues} class={[
          "rounded-xl border bg-white p-4 transition-shadow hover:shadow-sm",
          issue_card_classes(iss.severity_color)
        ]}>
          <div class="flex items-start gap-3">
            <span class={[
              "inline-flex items-center rounded-md p-1.5 shrink-0",
              issue_card_icon_classes(iss.severity_color)
            ]}>
              <.icon name={issue_icon(iss.type)} class="size-4" />
            </span>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class={[
                  "rounded px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider",
                  severity_badge_classes(iss.severity_color)
                ]}>
                  {iss.severity}
                </span>
                <span class="font-mono text-xs text-ink/50">{iss.type}</span>
              </div>
              <p class="mt-1.5 text-sm text-ink/80 font-medium">{iss.description}</p>
              <p :if={iss.business_impact != ""} class="mt-1.5 text-xs text-ink/60 italic">
                Impact — {iss.business_impact}
              </p>
            </div>
          </div>
        </li>
      </ul>
    </section>

    <section :if={@rendered.suggestions != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Suggested actions</h2>
        <span class="text-xs text-ink/60">{length(@rendered.suggestions)} step(s)</span>
      </div>

      <ol class="space-y-2">
        <li :for={{s, i} <- Enum.with_index(@rendered.suggestions, 1)} class="flex gap-3 items-start">
          <span class="inline-flex items-center justify-center shrink-0 rounded-full bg-purple text-white text-xs font-bold w-6 h-6">
            {i}
          </span>
          <span class="text-sm text-ink/80 leading-relaxed pt-0.5">{s}</span>
        </li>
      </ol>
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

  # Per-row card left-border tint (matches the row's status color).
  defp row_card_classes("emerald"), do: "border-emerald-400"
  defp row_card_classes("amber"), do: "border-amber-400"
  defp row_card_classes("rose"), do: "border-rose-400"
  defp row_card_classes(_), do: "border-line"

  # Issue card border tint (matches severity).
  defp issue_card_classes("rose"), do: "border-rose-200"
  defp issue_card_classes("amber"), do: "border-amber-200"
  defp issue_card_classes("emerald"), do: "border-emerald-200"
  defp issue_card_classes(_), do: "border-line"

  # Issue card icon background tint.
  defp issue_card_icon_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp issue_card_icon_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp issue_card_icon_classes("emerald"), do: "bg-emerald-100 text-emerald-700"
  defp issue_card_icon_classes(_), do: "bg-surface-lav text-ink/70"

  # Heroicon per issue type.
  defp issue_icon("missing_product"), do: "hero-cube-transparent"
  defp issue_icon("wrong_placement"), do: "hero-arrows-right-left"
  defp issue_icon("wrong_qty"), do: "hero-calculator"
  defp issue_icon("out_of_stock"), do: "hero-archive-box-x-mark"
  defp issue_icon("unauthorized_item"), do: "hero-no-symbol"
  defp issue_icon("photo_quality"), do: "hero-camera"
  defp issue_icon("mismatch"), do: "hero-exclamation-triangle"
  defp issue_icon(_), do: "hero-exclamation-circle"

  # Issue badge color classes — literal strings so Tailwind 4 can scan them.
  defp issue_badge_classes("missing_product"), do: "bg-rose-600 text-white"
  defp issue_badge_classes("wrong_placement"), do: "bg-amber-500 text-white"
  defp issue_badge_classes("wrong_qty"), do: "bg-amber-500 text-white"
  defp issue_badge_classes("out_of_stock"), do: "bg-orange-600 text-white"
  defp issue_badge_classes("unauthorized_item"), do: "bg-rose-600 text-white"
  defp issue_badge_classes("photo_quality"), do: "bg-zinc-600 text-white"
  defp issue_badge_classes("mismatch"), do: "bg-rose-600 text-white"
  defp issue_badge_classes(_), do: "bg-zinc-600 text-white"

  # Outlined-box classes that wrap the actual region on the shelf photo.
  # Color matches the badge above.
  defp issue_box_classes("missing_product"), do: "border-rose-500/90 bg-rose-500/10"
  defp issue_box_classes("wrong_placement"), do: "border-amber-500/90 bg-amber-500/10"
  defp issue_box_classes("wrong_qty"), do: "border-amber-500/90 bg-amber-500/10"
  defp issue_box_classes("out_of_stock"), do: "border-orange-600/90 bg-orange-600/10"
  defp issue_box_classes("unauthorized_item"), do: "border-rose-500/90 bg-rose-500/10"
  defp issue_box_classes("photo_quality"), do: "border-zinc-600/90 bg-zinc-600/10"
  defp issue_box_classes("mismatch"), do: "border-rose-500/90 bg-rose-500/10"
  defp issue_box_classes(_), do: "border-zinc-600/90 bg-zinc-600/10"

  # Render-time check: does the file backing `photo_path` actually exist
  # on disk? Defends against the case where the DB has a path but the
  # file got wiped (e.g. test suite's `clear_uploads/0` runs on the
  # shared filesystem, or `mix ecto.reset` between sessions). Avoids a
  # broken-image 404 on demo day.
  defp photo_on_disk?(nil), do: false

  defp photo_on_disk?("/" <> rel) do
    File.exists?(Path.join("priv/static", rel))
  end

  defp photo_on_disk?(_), do: false

  # Bounding-box positioning — converts a normalized %{x, y, w, h} (0-1
  # floats) to inline CSS percentages over the relatively-positioned image.
  defp bbox_style(%{x: x, y: y, w: w, h: h}) do
    "top: #{pct(y)}%; left: #{pct(x)}%; width: #{pct(w)}%; height: #{pct(h)}%;"
  end

  defp bbox_style(_), do: ""

  # For prices: anchor the badge to the top-left corner of the bbox, no
  # inflated rectangle — keeps the price tag visible without obscuring it.
  defp bbox_label_style(%{x: x, y: y}) do
    "top: #{pct(y)}%; left: #{pct(x)}%;"
  end

  defp bbox_label_style(_), do: ""

  defp pct(n) when is_number(n), do: Float.round(n * 100, 2)
  defp pct(_), do: 0

  # Drop duplicate prices: if Claude returned the same text + roughly-the-same
  # bbox twice, keep only one. Without bbox we fall back to text-only uniqueness.
  defp dedupe_prices(prices) when is_list(prices) do
    prices
    |> Enum.reduce({[], MapSet.new()}, fn p, {acc, seen} ->
      key = price_key(p)

      if MapSet.member?(seen, key) do
        {acc, seen}
      else
        {[p | acc], MapSet.put(seen, key)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp dedupe_prices(_), do: []

  defp price_key(%{text: text, bbox: %{x: x, y: y}}) do
    # Round to 2 decimals so near-identical bboxes from the model dedupe.
    {String.trim(text || ""), Float.round(x, 2), Float.round(y, 2)}
  end

  defp price_key(%{text: text, row: row, horizontal_position: hp}) do
    {String.trim(text || ""), row, hp}
  end

  defp price_key(_), do: :unknown

  # Severity badge classes — literal strings.
  defp severity_badge_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp severity_badge_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp severity_badge_classes("emerald"), do: "bg-emerald-100 text-emerald-700"
  defp severity_badge_classes(_), do: "bg-surface-lav text-ink/80"

  defp status_classes("pending"), do: "bg-surface-lav text-ink/80"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-surface-lav"
end
