defmodule ShowcaseWeb.RestaurantCompliance.RulesetsLive do
  @moduledoc """
  Ruleset manager at `/restaurant-compliance/rulesets`. Lists existing
  rulesets with their reference image thumbnails, plus a form to add a
  new ruleset (name + description + rules text + multi-file ref upload).
  """
  use ShowcaseWeb, :live_view

  alias Showcase.RestaurantCompliance
  alias Showcase.RestaurantCompliance.Ruleset

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Compliance rulesets")
     |> assign(:rulesets, RestaurantCompliance.list_rulesets())
     |> assign(:new_ruleset, %{"name" => "", "description" => "", "rules_text" => default_rules_text()})
     |> allow_upload(:references,
       accept: ~w(.png .jpg .jpeg),
       max_entries: 5,
       max_file_size: 5_000_000
     )}
  end

  defp default_rules_text do
    """
    Official Mise en Place Compliance Guide:
    Viewpoint: Direct top-down, providing a clear layout of all settings.

    Central Elements:
    - Bottle Facings: Bottles on the lazy Susan are clean and face outward toward the diners.
    - Card Placement: A formalized red text card with specific standard instructions is centered.
    - Grinders: Polished salt and pepper grinders are in a specific, clean position.

    Place Settings:
    - Flatware: Knives are perfectly parallel to the right, forks to the left. All are aligned precisely with the plate.
    - Napkins: Clean, dark grey linen napkins are neatly folded on pristine white plates.
    - Glassware: Water, red, and white wine glasses are clean, polished, and arranged in a consistent pattern to the upper right of each setting.
    - Dishes: Clean side plates and bowls are set for courses.

    General:
    - Floor must be free of food debris, dirt, or fallen napkins.
    - Tables must be cleared and reset between services.
    - Empty bottles and used dishes must not be left on tables.
    """
  end

  @impl true
  def handle_event("validate_ruleset", %{"ruleset" => attrs}, socket) do
    # Persist typed inputs across upload-progress re-renders.
    {:noreply, assign(socket, :new_ruleset, attrs)}
  end

  def handle_event("validate_ruleset", _params, socket), do: {:noreply, socket}

  def handle_event("create_ruleset", %{"ruleset" => attrs}, socket) do
    bytes_list =
      consume_uploaded_entries(socket, :references, fn %{path: tmp}, _entry ->
        {:ok, File.read!(tmp)}
      end)

    case RestaurantCompliance.create_ruleset_with_references(attrs, bytes_list) do
      {:ok, _rs} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ruleset added.")
         |> assign(:rulesets, RestaurantCompliance.list_rulesets())
         |> assign(:new_ruleset, %{"name" => "", "description" => "", "rules_text" => default_rules_text()})}

      {:error, changeset} ->
        msg =
          if is_struct(changeset, Ecto.Changeset),
            do: "Could not save: #{format_changeset_errors(changeset)}",
            else: "Could not save ruleset."

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_ruleset", %{"ruleset_id" => id}, socket) do
    {rid, _} = Integer.parse(id)

    case RestaurantCompliance.delete_ruleset(rid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ruleset deleted (and all its inspections).")
         |> assign(:rulesets, RestaurantCompliance.list_rulesets())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete: #{inspect(reason)}")}
    end
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
          <div class="flex gap-2 items-center">
            <a
              href="/restaurant-compliance"
              class="rounded-lg border border-line bg-white px-3 py-2 text-sm text-ink/80 hover:bg-surface-lav"
            >
              ← Inspections
            </a>
            <a href="/" class="ml-2 text-sm text-ink/60 hover:text-purple transition-colors">
              Dashboard
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
            Compliance rulesets
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            Define the standard once. Inspectors compare every restaurant against it.
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

        <%!-- Existing rulesets --%>
        <section>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="font-heading text-lg font-bold text-ink">
              Existing rulesets ({length(@rulesets)})
            </h2>
          </div>

          <p :if={@rulesets == []} class="text-sm text-ink/60">
            No rulesets yet — add one below.
          </p>

          <div :if={@rulesets != []} class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.ruleset_card :for={rs <- @rulesets} ruleset={rs} />
          </div>
        </section>

        <%!-- Add ruleset form --%>
        <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
          <h2 class="font-heading text-lg font-bold text-ink mb-4">Add ruleset</h2>

          <form phx-submit="create_ruleset" phx-change="validate_ruleset" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Name</label>
                <input
                  name="ruleset[name]"
                  value={@new_ruleset["name"] || ""}
                  required
                  class="w-full rounded-lg border border-line px-3 py-2"
                  placeholder="e.g. Mise-en-place standards"
                />
              </div>
              <div>
                <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Description</label>
                <input
                  name="ruleset[description]"
                  value={@new_ruleset["description"] || ""}
                  class="w-full rounded-lg border border-line px-3 py-2"
                  placeholder="(optional) short tag"
                />
              </div>
            </div>

            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">
                Rules document
              </label>
              <textarea
                name="ruleset[rules_text]"
                rows="14"
                required
                class="w-full rounded-lg border border-line px-3 py-2 font-mono text-xs leading-relaxed bg-surface-lav-2/30"
              >{@new_ruleset["rules_text"] || ""}</textarea>
              <p class="mt-1 text-xs text-ink/50">
                Plain text. The AI parses this rule-by-rule when grading inspection photos.
              </p>
            </div>

            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">
                Reference images (max 5)
              </label>
              <.live_file_input upload={@uploads.references} class="block w-full text-sm" />
              <ul class="mt-2 space-y-1">
                <li :for={entry <- @uploads.references.entries} class="text-xs text-ink/70">
                  {entry.client_name} — {entry.progress}%
                  <div
                    :for={err <- upload_errors(@uploads.references, entry)}
                    class="text-rose-600"
                  >
                    {upload_error_to_string(err)}
                  </div>
                </li>
              </ul>
              <p class="mt-1 text-xs text-ink/50">PNG/JPEG, max 5 MB each. Optional but recommended.</p>
            </div>

            <div>
              <button
                type="submit"
                class="rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90"
              >
                Save ruleset
              </button>
            </div>
          </form>
        </section>
      </main>
    </div>
    """
  end

  attr :ruleset, Ruleset, required: true

  defp ruleset_card(assigns) do
    paths = Ruleset.reference_paths(assigns.ruleset)
    assigns = assign(assigns, :ref_paths, paths)

    ~H"""
    <article class="rounded-2xl border border-line bg-white p-5 shadow-sm">
      <div class="flex items-start justify-between gap-3 mb-3">
        <div class="flex items-start gap-3 min-w-0 flex-1">
          <span class="inline-flex items-center justify-center rounded-lg bg-purple/10 text-purple p-2 shrink-0">
            <.icon name="hero-clipboard-document-list" class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <h3 class="font-heading font-bold text-ink truncate">{@ruleset.name}</h3>
            <p :if={@ruleset.description} class="mt-0.5 text-xs text-ink/60 line-clamp-2">
              {@ruleset.description}
            </p>
          </div>
        </div>
        <button
          type="button"
          phx-click="delete_ruleset"
          phx-value-ruleset_id={@ruleset.id}
          data-confirm={"Delete ruleset \"#{@ruleset.name}\" and all its inspections?"}
          class="text-xs text-rose-600 hover:text-rose-800 underline shrink-0"
        >
          Delete
        </button>
      </div>

      <div :if={@ref_paths != []} class="flex flex-wrap gap-2 mb-3">
        <img
          :for={path <- @ref_paths}
          src={path}
          alt="Reference standard"
          class="w-20 h-20 object-cover rounded-lg border border-line bg-surface-lav-2"
        />
      </div>
      <p :if={@ref_paths == []} class="text-xs text-ink/40 italic mb-3">
        No reference images attached.
      </p>

      <details class="rounded border border-line">
        <summary class="cursor-pointer px-3 py-2 text-xs uppercase tracking-wide text-ink/60">
          Rules document
        </summary>
        <pre class="bg-surface-lav-2/30 text-xs text-ink/80 p-3 overflow-auto max-h-64 whitespace-pre-wrap font-mono leading-relaxed"><%= @ruleset.rules_text %></pre>
      </details>
    </article>
    """
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 5 MB)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported file type (.png, .jpg)."
  defp upload_error_to_string(:too_many_files), do: "Maximum 5 reference images."
  defp upload_error_to_string(_), do: "Upload error."
end
