defmodule ShowcaseWeb.RestaurantCompliance.InspectionsLive do
  @moduledoc """
  Landing page at `/restaurant-compliance` — shows existing rulesets
  (with link to ruleset manager) and lists all inspections plus a
  "Schedule inspection" form that pairs a ruleset with a restaurant.
  No role switcher; this is a single page everyone sees.
  """
  use ShowcaseWeb, :live_view

  alias Showcase.RestaurantCompliance
  alias Showcase.RestaurantCompliance.{Ruleset, Inspection, VisionPipeline}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      for inspection <- RestaurantCompliance.list_inspections() do
        Phoenix.PubSub.subscribe(Showcase.PubSub, VisionPipeline.topic(inspection.id))
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "Restaurant Compliance")
     |> load_all()}
  end

  defp load_all(socket) do
    socket
    |> assign(:rulesets, RestaurantCompliance.list_rulesets())
    |> assign(:inspections, RestaurantCompliance.list_inspections())
  end

  @impl true
  def handle_event("create_inspection", %{"inspection" => attrs}, socket) do
    case RestaurantCompliance.create_inspection(attrs) do
      {:ok, _i} ->
        {:noreply,
         socket
         |> put_flash(:info, "Inspection scheduled.")
         |> load_all()}

      {:error, changeset} ->
        msg = "Could not schedule: #{format_changeset_errors(changeset)}"
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_inspection", %{"inspection_id" => id}, socket) do
    {iid, _} = Integer.parse(id)

    case RestaurantCompliance.delete_inspection(iid) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Inspection removed.") |> load_all()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:restaurant_compliance, _phase, _id}, socket) do
    {:noreply, load_all(socket)}
  end

  def handle_info({:restaurant_compliance, :failed, _id, _reason}, socket) do
    {:noreply, load_all(socket)}
  end

  defp format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <div class="flex items-center gap-3">
            <a
              href="/restaurant-compliance/rulesets"
              class="rounded-lg border border-line bg-white px-3 py-2 text-sm text-ink/80 hover:bg-surface-lav"
            >
              Manage rulesets
            </a>
            <a href="/" class="ml-2 text-sm text-ink/60 hover:text-purple transition-colors">
              &larr; Dashboard
            </a>
          </div>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Neurony · Restaurant Compliance
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            Restaurant inspections
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            Inspector uploads four to five photos per visit. AI grades them rule-by-rule against the chosen mise-en-place ruleset and surfaces every violation with the photo that proves it.
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

        <%!-- Rulesets section --%>
        <section class="space-y-3">
          <div class="flex items-baseline justify-between">
            <h2 class="font-heading text-lg font-bold text-ink">Active rulesets</h2>
            <a
              href="/restaurant-compliance/rulesets"
              class="text-sm text-purple hover:underline"
            >
              Manage rulesets →
            </a>
          </div>

          <div :if={@rulesets == []} class="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
            No rulesets yet — add one on the
            <a href="/restaurant-compliance/rulesets" class="underline">rulesets page</a>.
          </div>

          <div :if={@rulesets != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <.ruleset_card :for={rs <- @rulesets} ruleset={rs} />
          </div>
        </section>

        <%!-- Create inspection form --%>
        <section :if={@rulesets != []} class="rounded-2xl border border-line bg-white p-6 shadow-sm">
          <h2 class="font-heading text-lg font-bold text-ink mb-4">Schedule an inspection</h2>
          <form phx-submit="create_inspection" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3 items-end">
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Restaurant</label>
              <input
                name="inspection[restaurant_name]"
                required
                class="w-full rounded-lg border border-line px-3 py-2"
                placeholder="e.g. Bistro Floreasca"
              />
            </div>
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Inspector</label>
              <input
                name="inspection[inspector_name]"
                class="w-full rounded-lg border border-line px-3 py-2"
                placeholder="(optional)"
              />
            </div>
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Ruleset</label>
              <select name="inspection[ruleset_id]" required class="w-full rounded-lg border border-line px-3 py-2">
                <option :for={rs <- @rulesets} value={rs.id}>{rs.name}</option>
              </select>
            </div>
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Due date</label>
              <input
                name="inspection[due_date]"
                type="date"
                required
                value={Date.utc_today() |> Date.to_iso8601()}
                class="w-full rounded-lg border border-line px-3 py-2"
              />
            </div>
            <div class="md:col-span-2 lg:col-span-4">
              <button
                type="submit"
                class="rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90"
              >
                Schedule inspection
              </button>
              <span class="ml-3 text-xs text-ink/60">
                Photos are uploaded on the inspection detail page.
              </span>
            </div>
          </form>
        </section>

        <%!-- All inspections --%>
        <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
          <div class="flex items-baseline justify-between mb-4">
            <h2 class="font-heading text-lg font-bold text-ink">
              All inspections ({length(@inspections)})
            </h2>
          </div>

          <p :if={@inspections == []} class="text-sm text-ink/60">
            No inspections yet — use the form above to schedule the first one.
          </p>

          <table :if={@inspections != []} class="w-full text-sm">
            <thead class="text-xs uppercase tracking-wide text-ink/60">
              <tr>
                <th class="text-left py-2">Restaurant</th>
                <th class="text-left py-2">Ruleset</th>
                <th class="text-left py-2">Due</th>
                <th class="text-left py-2">Status</th>
                <th class="text-left py-2">Score</th>
                <th class="text-right py-2">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line">
              <tr :for={i <- @inspections}>
                <td class="py-2">
                  <a href={"/restaurant-compliance/#{i.id}"} class="font-medium text-ink hover:underline">
                    {i.restaurant_name}
                  </a>
                  <div :if={i.inspector_name && i.inspector_name != ""} class="text-xs text-ink/50">
                    {i.inspector_name}
                  </div>
                </td>
                <td class="py-2 text-ink/70">{i.ruleset && i.ruleset.name}</td>
                <td class="py-2 text-ink/70">{i.due_date}</td>
                <td class="py-2">
                  <span class={["rounded px-2 py-0.5 text-xs", status_classes(i.status)]}>
                    {i.status}
                  </span>
                </td>
                <td class="py-2">
                  <span :if={score(i)} class={["rounded-full px-2.5 py-0.5 text-xs font-bold", score_pill_classes(score(i))]}>
                    {score(i)}%
                  </span>
                </td>
                <td class="py-2 text-right space-x-3">
                  <a href={"/restaurant-compliance/#{i.id}"} class="text-xs text-ink/80 underline hover:text-ink">
                    Open
                  </a>
                  <button
                    type="button"
                    phx-click="delete_inspection"
                    phx-value-inspection_id={i.id}
                    data-confirm={"Delete inspection for \"#{i.restaurant_name}\"?"}
                    class="text-xs text-rose-600 hover:text-rose-800 underline"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </main>
    </div>
    """
  end

  attr :ruleset, Ruleset, required: true

  defp ruleset_card(assigns) do
    paths = Ruleset.reference_paths(assigns.ruleset)
    assigns = assign(assigns, :ref_count, length(paths))

    ~H"""
    <article class="rounded-2xl border border-line bg-white p-5 shadow-sm">
      <div class="flex items-start gap-3">
        <span class="inline-flex items-center justify-center rounded-lg bg-purple/10 text-purple p-2">
          <.icon name="hero-clipboard-document-check" class="size-5" />
        </span>
        <div class="flex-1 min-w-0">
          <h3 class="font-heading font-bold text-ink truncate">{@ruleset.name}</h3>
          <p class="mt-1 text-xs text-ink/60 line-clamp-2">{@ruleset.description}</p>
          <div class="mt-3 flex items-center gap-2 text-xs text-ink/50">
            <.icon name="hero-photo" class="size-3.5" />
            <span>{@ref_count} reference {if @ref_count == 1, do: "image", else: "images"}</span>
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp score(%Inspection{result: %{"compliance_score" => s}}) when is_number(s), do: s
  defp score(_), do: nil

  defp score_pill_classes(s) when is_number(s) and s >= 90, do: "bg-emerald-100 text-emerald-800"
  defp score_pill_classes(s) when is_number(s) and s >= 60, do: "bg-amber-100 text-amber-800"
  defp score_pill_classes(_), do: "bg-rose-100 text-rose-800"

  defp status_classes("pending"), do: "bg-surface-lav text-ink/80"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-surface-lav"
end
