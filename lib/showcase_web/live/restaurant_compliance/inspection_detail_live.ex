defmodule ShowcaseWeb.RestaurantCompliance.InspectionDetailLive do
  @moduledoc """
  Detail view for a single Inspection at `/restaurant-compliance/:id`.

  Three states based on `inspection.status`:
    * `pending` — upload photos, then run analysis
    * `analyzing` — banner
    * `failed` — rose banner + error_reason
    * `complete` — the showcase view: score stripe, rule checklist,
      photo gallery with per-photo violations, remediation steps,
      raw JSON inspector
  """
  use ShowcaseWeb, :live_view

  alias Showcase.RestaurantCompliance
  alias Showcase.RestaurantCompliance.{Inspection, Ruleset}
  alias Showcase.RestaurantCompliance.Impl.ResultRenderer
  alias Showcase.RestaurantCompliance.VisionPipeline
  alias Showcase.Common.AnthropicClient.Types.Usage

  alias ShowcaseWeb.Components.{CostBadge, JSONInspector}

  import CostBadge, only: [cost_badge: 1]
  import JSONInspector, only: [json_inspector: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    inspection = RestaurantCompliance.get_inspection!(String.to_integer(id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Showcase.PubSub, VisionPipeline.topic(inspection.id))
    end

    socket =
      socket
      |> allow_upload(:photos,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 8,
        max_file_size: 8_000_000
      )
      |> assign_inspection(inspection)

    {:ok, socket}
  end

  defp assign_inspection(socket, inspection) do
    rendered = if inspection.result, do: ResultRenderer.render(inspection.result), else: nil
    usage = if inspection.usage, do: usage_struct(inspection.usage), else: nil

    socket
    |> assign(:inspection, inspection)
    |> assign(:rendered, rendered)
    |> assign(:usage, usage)
  end

  defp usage_struct(%{"input_tokens" => i, "output_tokens" => o, "cost_estimate_cents" => c}) do
    %Usage{input_tokens: i, output_tokens: o, cost_estimate_cents: c * 1.0}
  end

  defp usage_struct(_), do: nil

  @impl true
  def handle_event("run_analysis", _params, socket) do
    case Inspection.photo_paths(socket.assigns.inspection) do
      [] ->
        {:noreply, put_flash(socket, :error, "Upload at least one photo first.")}

      _ ->
        RestaurantCompliance.enqueue_analysis(socket.assigns.inspection.id)
        {:noreply, put_flash(socket, :info, "Analysis enqueued.")}
    end
  end

  def handle_event("validate_photos", _params, socket), do: {:noreply, socket}

  def handle_event("upload_photos", _params, socket) do
    bytes_list =
      consume_uploaded_entries(socket, :photos, fn %{path: tmp}, _entry ->
        {:ok, File.read!(tmp)}
      end)

    if bytes_list == [] do
      {:noreply, put_flash(socket, :error, "No photos uploaded.")}
    else
      Enum.reduce_while(bytes_list, {:ok, socket.assigns.inspection}, fn bytes, {:ok, ins} ->
        case RestaurantCompliance.save_inspection_photo(ins, bytes) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, _last} ->
          refreshed = RestaurantCompliance.get_inspection!(socket.assigns.inspection.id)

          {:noreply,
           socket
           |> put_flash(:info, "#{length(bytes_list)} photo(s) uploaded.")
           |> assign_inspection(refreshed)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save photos.")}
      end
    end
  end

  @impl true
  def handle_info({:restaurant_compliance, :failed, _id, _reason}, socket) do
    refreshed = RestaurantCompliance.get_inspection!(socket.assigns.inspection.id)
    {:noreply, assign_inspection(socket, refreshed)}
  end

  def handle_info({:restaurant_compliance, _phase, _id}, socket) do
    refreshed = RestaurantCompliance.get_inspection!(socket.assigns.inspection.id)
    {:noreply, assign_inspection(socket, refreshed)}
  end

  @impl true
  def render(assigns) do
    photo_paths = Inspection.photo_paths(assigns.inspection)
    ref_paths = Ruleset.reference_paths(assigns.inspection.ruleset)

    assigns =
      assigns
      |> assign(:photo_paths, photo_paths)
      |> assign(:ref_paths, ref_paths)

    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/restaurant-compliance" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Back to inspections
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Inspection · {@inspection.ruleset.name}
          </p>
          <div class="mt-2 flex items-baseline gap-3 flex-wrap">
            <h1 class="font-heading font-bold text-3xl text-ink tracking-tight">
              {@inspection.restaurant_name}
            </h1>
            <span class={["rounded px-2 py-0.5 text-xs", status_classes(@inspection.status)]}>
              {@inspection.status}
            </span>
          </div>
          <p class="mt-2 font-body text-sm text-ink/60">
            Due {@inspection.due_date}
            <%= if @inspection.inspector_name && @inspection.inspector_name != "" do %>
              · Inspector: {@inspection.inspector_name}
            <% end %>
          </p>
        </div>
      </div>

      <main class="max-w-7xl mx-auto px-6 py-6 space-y-6">
        <div :if={@flash["info"]} class="rounded-2xl border border-emerald-200 bg-emerald-50 shadow-sm px-4 py-2 text-sm text-emerald-800">
          {@flash["info"]}
        </div>
        <div :if={@flash["error"]} class="rounded-2xl border border-rose-200 bg-rose-50 shadow-sm px-4 py-2 text-sm text-rose-800">
          {@flash["error"]}
        </div>

        <%= case @inspection.status do %>
          <% "pending" -> %>
            <.pending_panel
              inspection={@inspection}
              uploads={@uploads}
              photo_paths={@photo_paths}
              ref_paths={@ref_paths}
            />

          <% "analyzing" -> %>
            <div class="rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800 flex items-center gap-3">
              <span class="inline-block size-3 rounded-full bg-blue-500 animate-pulse"></span>
              Analyzing… Claude is comparing {length(@photo_paths)} photo(s) against the ruleset.
            </div>

          <% "failed" -> %>
            <div class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
              <p class="font-medium">Analysis failed</p>
              <p class="mt-1">{@inspection.error_reason}</p>
              <button
                type="button"
                phx-click="run_analysis"
                class="mt-3 rounded bg-rose-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-rose-700"
              >
                Re-run analysis
              </button>
            </div>

          <% "complete" -> %>
            <.result_panel
              rendered={@rendered}
              usage={@usage}
              inspection={@inspection}
              photo_paths={@photo_paths}
              ref_paths={@ref_paths}
            />
        <% end %>
      </main>
    </div>
    """
  end

  attr :inspection, Inspection, required: true
  attr :uploads, :map, required: true
  attr :photo_paths, :list, required: true
  attr :ref_paths, :list, required: true

  defp pending_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-4">
      <h2 class="font-heading text-lg font-bold text-ink">Add inspection photos</h2>
      <p class="text-sm text-ink/60">
        Pick up to 8 photos from the restaurant — flatware close-ups, table-wide top-downs, floor shots. The AI references them by index in its report.
      </p>

      <form phx-submit="upload_photos" phx-change="validate_photos" class="space-y-3">
        <.live_file_input upload={@uploads.photos} class="block w-full text-sm" />
        <ul class="space-y-1">
          <li :for={entry <- @uploads.photos.entries} class="text-xs text-ink/70">
            {entry.client_name} — {entry.progress}%
            <div :for={err <- upload_errors(@uploads.photos, entry)} class="text-rose-600">
              {upload_error_to_string(err)}
            </div>
          </li>
        </ul>
        <button
          type="submit"
          disabled={@uploads.photos.entries == []}
          class="rounded bg-ink px-4 py-2 text-sm font-semibold text-white hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Upload photos
        </button>
      </form>
    </section>

    <section :if={@photo_paths != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-4">
      <div class="flex items-baseline justify-between">
        <h2 class="font-heading text-lg font-bold text-ink">
          Uploaded photos ({length(@photo_paths)})
        </h2>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
        <figure :for={{path, idx} <- Enum.with_index(@photo_paths, 1)} class="relative">
          <img
            src={path}
            alt={"Inspection photo #{idx}"}
            class="w-full aspect-square object-cover rounded-lg border border-line bg-surface-lav-2"
          />
          <figcaption class="absolute top-2 left-2 rounded bg-ink/80 text-white text-[10px] font-bold uppercase px-1.5 py-0.5">
            Photo {idx}
          </figcaption>
        </figure>
      </div>

      <button
        type="button"
        phx-click="run_analysis"
        class="w-full rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90"
      >
        Run compliance analysis
      </button>
    </section>

    <section :if={@ref_paths != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm space-y-3">
      <h2 class="font-heading text-sm font-bold text-ink/70 uppercase tracking-wide">
        Compared against these reference standards
      </h2>
      <div class="flex flex-wrap gap-3">
        <figure :for={{path, idx} <- Enum.with_index(@ref_paths, 1)} class="relative">
          <img
            src={path}
            alt={"Reference standard #{idx}"}
            class="w-32 h-32 object-cover rounded-lg border border-line bg-surface-lav-2"
          />
          <figcaption class="absolute top-1 left-1 rounded bg-purple/90 text-white text-[10px] font-bold uppercase px-1 py-0.5">
            Ref {idx}
          </figcaption>
        </figure>
      </div>
    </section>
    """
  end

  attr :rendered, :map, required: true
  attr :usage, :any, required: true
  attr :inspection, Inspection, required: true
  attr :photo_paths, :list, required: true
  attr :ref_paths, :list, required: true

  defp result_panel(assigns) do
    # Group photo violations by index so the photo gallery can attach them.
    violations_by_photo =
      assigns.rendered.photo_violations
      |> Enum.reduce(%{}, fn pv, acc -> Map.put(acc, pv.photo_index, pv.issues) end)

    assigns = assign(assigns, :violations_by_photo, violations_by_photo)

    ~H"""
    <div :if={@rendered.partial?} class="rounded-2xl border border-amber-200 bg-amber-50 shadow-sm px-4 py-2 text-xs text-amber-800">
      The AI response was truncated — showing salvaged fields via ResilientJSONParser.
    </div>

    <%!-- 1. Score stripe --%>
    <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-center">
        <div class="lg:col-span-3">
          <div class="text-xs uppercase tracking-wider text-ink/60 mb-1">Compliance score</div>
          <div class="flex items-baseline gap-2">
            <span class={["font-heading text-5xl font-bold tracking-tight", score_text_classes(@rendered.gauge_pct)]}>
              {@rendered.gauge_pct}
            </span>
            <span class="text-2xl text-ink/40 font-heading">/ 100</span>
          </div>
          <div class="mt-3 h-2 rounded-full bg-surface-lav-2 overflow-hidden">
            <div
              class={["h-full transition-all", score_bar_classes(@rendered.gauge_pct)]}
              style={"width: #{@rendered.gauge_pct}%"}
            >
            </div>
          </div>
        </div>

        <div class="lg:col-span-6">
          <div class="text-xs uppercase tracking-wider text-ink/60 mb-1">Summary</div>
          <p class="text-sm text-ink/80 leading-relaxed">{@rendered.overall_summary}</p>
        </div>

        <div class="lg:col-span-3 space-y-2">
          <div class="grid grid-cols-3 gap-2">
            <.count_pill label="Passed" count={@rendered.pass_count} tone="emerald" icon="hero-check" />
            <.count_pill label="Partial" count={@rendered.partial_count} tone="amber" icon="hero-minus" />
            <.count_pill label="Failed" count={@rendered.fail_count} tone="rose" icon="hero-x-mark" />
          </div>
          <div :if={@rendered.not_applicable_count > 0} class="text-xs text-ink/50 text-center">
            +{@rendered.not_applicable_count} not applicable
          </div>
          <div class="flex items-center justify-center gap-2 pt-1">
            <.cost_badge :if={@usage} usage={@usage} />
          </div>
        </div>
      </div>

      <div :if={@photo_paths != []} class="mt-5 pt-5 border-t border-line">
        <div class="flex gap-2 overflow-x-auto pb-1">
          <img
            :for={{path, idx} <- Enum.with_index(@photo_paths, 1)}
            src={path}
            alt={"Inspection photo #{idx}"}
            title={"Photo #{idx}"}
            class="w-14 h-14 object-cover rounded-md border border-line bg-surface-lav-2 shrink-0"
          />
        </div>
      </div>
    </section>

    <%!-- 2. Rule checklist - the centerpiece --%>
    <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Rule-by-rule checklist</h2>
        <p class="text-xs text-ink/60">
          {@rendered.total_rules} rules evaluated
        </p>
      </div>

      <div class="space-y-3">
        <div
          :for={ev <- @rendered.rule_evaluations}
          class={["rounded-xl border-l-4 bg-surface-lav-2/40 p-4", rule_card_classes(ev.status_color)]}
        >
          <div class="flex items-start gap-3">
            <span class={[
              "inline-flex items-center justify-center rounded-full p-1.5 shrink-0",
              icon_bg_classes(ev.status_color)
            ]}>
              <.icon name={ev.status_icon} class="size-5" />
            </span>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <h3 class="font-heading font-semibold text-ink">{ev.rule}</h3>
                <span class={[
                  "rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider",
                  status_pill_classes(ev.status_color)
                ]}>
                  {ev.status}
                </span>
                <span class={[
                  "rounded px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider",
                  severity_pill_classes(ev.severity_color)
                ]}>
                  {ev.severity}
                </span>
              </div>

              <p :if={ev.evidence != ""} class="mt-1.5 text-sm text-ink/70 italic leading-relaxed">
                {ev.evidence}
              </p>

              <div :if={ev.photo_indices != []} class="mt-3 flex flex-wrap gap-1.5">
                <span class="text-xs text-ink/50 mr-1">Photos:</span>
                <%= for idx <- ev.photo_indices do %>
                  <%= if photo_at(@photo_paths, idx) do %>
                    <a href={"#photo-#{idx}"} class="block">
                      <img
                        src={photo_at(@photo_paths, idx)}
                        alt={"Photo #{idx}"}
                        title={"Photo #{idx}"}
                        class="w-12 h-12 object-cover rounded-md border border-line bg-surface-lav-2 hover:border-purple transition-colors"
                      />
                    </a>
                  <% else %>
                    <span class="inline-flex items-center justify-center w-12 h-12 rounded-md border border-dashed border-line bg-surface-lav-2 text-[10px] text-ink/40">
                      #{idx}
                    </span>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- 3. Photo gallery with per-photo violation cards --%>
    <section :if={@photo_paths != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Photo evidence</h2>
        <p class="text-xs text-ink/60">{length(@photo_paths)} photos</p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <article
          :for={{path, idx} <- Enum.with_index(@photo_paths, 1)}
          id={"photo-#{idx}"}
          class="rounded-xl border border-line bg-surface-lav-2/30 overflow-hidden"
        >
          <div class="relative">
            <img
              src={path}
              alt={"Photo #{idx}"}
              class="w-full aspect-[4/3] object-cover bg-surface-lav-2"
            />
            <span class="absolute top-2 left-2 rounded bg-ink/80 text-white text-[10px] font-bold uppercase px-1.5 py-0.5">
              Photo {idx}
            </span>
            <%= case Map.get(@violations_by_photo, idx, []) do %>
              <% [] -> %>
                <span class="absolute top-2 right-2 rounded-full bg-emerald-500 text-white text-[10px] font-bold uppercase px-2 py-0.5 flex items-center gap-1">
                  <.icon name="hero-check" class="size-3" /> Clean
                </span>
              <% issues -> %>
                <span class="absolute top-2 right-2 rounded-full bg-rose-500 text-white text-[10px] font-bold uppercase px-2 py-0.5 flex items-center gap-1">
                  <.icon name="hero-exclamation-triangle" class="size-3" /> {length(issues)}
                </span>
            <% end %>
          </div>

          <div class="p-3 space-y-2 min-h-[5rem]">
            <%= case Map.get(@violations_by_photo, idx, []) do %>
              <% [] -> %>
                <p class="text-xs text-ink/50 italic">No violations detected in this photo.</p>
              <% issues -> %>
                <div :for={iss <- issues} class={[
                  "rounded-md border-l-2 bg-white px-2.5 py-1.5",
                  violation_classes(iss.severity_color)
                ]}>
                  <div class="flex items-start gap-2">
                    <span class={[
                      "shrink-0 inline-block rounded-sm px-1 py-px text-[9px] font-bold uppercase",
                      severity_pill_classes(iss.severity_color)
                    ]}>
                      {iss.severity}
                    </span>
                    <p class="text-xs text-ink/80 leading-snug">{iss.description}</p>
                  </div>
                </div>
            <% end %>
          </div>
        </article>
      </div>
    </section>

    <%!-- 4. Remediation steps --%>
    <section :if={@rendered.remediation_steps != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h2 class="font-heading text-lg font-bold text-ink">Remediation steps</h2>
        <span class="text-xs text-ink/60">
          {length(@rendered.remediation_steps)} {if length(@rendered.remediation_steps) == 1, do: "step", else: "steps"}
        </span>
      </div>
      <ol class="space-y-2">
        <li
          :for={{step, i} <- Enum.with_index(@rendered.remediation_steps, 1)}
          class="flex gap-3 items-start"
        >
          <span class="inline-flex items-center justify-center shrink-0 rounded-full bg-purple text-white text-xs font-bold w-6 h-6">
            {i}
          </span>
          <span class="text-sm text-ink/80 leading-relaxed pt-0.5">{step}</span>
        </li>
      </ol>
    </section>

    <%!-- 5. Reference image strip --%>
    <section :if={@ref_paths != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <h2 class="font-heading text-sm font-bold text-ink/70 uppercase tracking-wide mb-3">
        Compared against these reference standards
      </h2>
      <div class="flex flex-wrap gap-3">
        <figure :for={{path, idx} <- Enum.with_index(@ref_paths, 1)} class="relative">
          <img
            src={path}
            alt={"Reference standard #{idx}"}
            class="w-28 h-28 object-cover rounded-lg border border-line bg-surface-lav-2"
          />
          <figcaption class="absolute top-1 left-1 rounded bg-purple/90 text-white text-[10px] font-bold uppercase px-1 py-0.5">
            Ref {idx}
          </figcaption>
        </figure>
      </div>
    </section>

    <%!-- 6. Raw JSON inspector --%>
    <.json_inspector data={@inspection.result} />
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :tone, :string, required: true
  attr :icon, :string, required: true

  defp count_pill(assigns) do
    ~H"""
    <div class={["rounded-lg px-2 py-1.5 text-center border", count_pill_classes(@tone)]}>
      <div class="flex items-center justify-center gap-1">
        <.icon name={@icon} class="size-3" />
        <span class="text-lg font-bold leading-none">{@count}</span>
      </div>
      <div class="text-[9px] uppercase tracking-wider mt-0.5">{@label}</div>
    </div>
    """
  end

  defp count_pill_classes("emerald"), do: "bg-emerald-50 border-emerald-200 text-emerald-700"
  defp count_pill_classes("amber"), do: "bg-amber-50 border-amber-200 text-amber-700"
  defp count_pill_classes("rose"), do: "bg-rose-50 border-rose-200 text-rose-700"
  defp count_pill_classes(_), do: "bg-surface-lav border-line text-ink/70"

  defp rule_card_classes("emerald"), do: "border-emerald-400"
  defp rule_card_classes("amber"), do: "border-amber-400"
  defp rule_card_classes("rose"), do: "border-rose-400"
  defp rule_card_classes(_), do: "border-line"

  defp icon_bg_classes("emerald"), do: "bg-emerald-100 text-emerald-700"
  defp icon_bg_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp icon_bg_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp icon_bg_classes(_), do: "bg-surface-lav text-ink/60"

  defp status_pill_classes("emerald"), do: "bg-emerald-100 text-emerald-800"
  defp status_pill_classes("amber"), do: "bg-amber-100 text-amber-800"
  defp status_pill_classes("rose"), do: "bg-rose-100 text-rose-800"
  defp status_pill_classes(_), do: "bg-surface-lav text-ink/70"

  defp severity_pill_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp severity_pill_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp severity_pill_classes(_), do: "bg-surface-lav text-ink/70"

  defp violation_classes("rose"), do: "border-rose-400"
  defp violation_classes("amber"), do: "border-amber-400"
  defp violation_classes(_), do: "border-line"

  defp score_text_classes(s) when is_number(s) and s >= 90, do: "text-emerald-600"
  defp score_text_classes(s) when is_number(s) and s >= 60, do: "text-amber-600"
  defp score_text_classes(_), do: "text-rose-600"

  defp score_bar_classes(s) when is_number(s) and s >= 90, do: "bg-emerald-500"
  defp score_bar_classes(s) when is_number(s) and s >= 60, do: "bg-amber-500"
  defp score_bar_classes(_), do: "bg-rose-500"

  defp photo_at(paths, idx) when is_list(paths) and is_integer(idx) and idx >= 1 do
    Enum.at(paths, idx - 1)
  end

  defp photo_at(_, _), do: nil

  defp status_classes("pending"), do: "bg-surface-lav text-ink/80"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-surface-lav"

  defp upload_error_to_string(:too_large), do: "Photo too large (max 8 MB)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported file (.png, .jpg)."
  defp upload_error_to_string(:too_many_files), do: "Maximum 8 photos."
  defp upload_error_to_string(_), do: "Upload error."
end
