defmodule ShowcaseWeb.Planogram.PlanogramLive do
  @moduledoc """
  Single LiveView at `/planogram`. Carries three roles
  (`merchandiser` / `manager` / `admin`) swapped via in-page session.

  Task 10 wires the role chrome + the full Merchandiser panel (bucketed
  audit tasks, Run analysis / Force truncation / Open on phone). Manager
  + Admin panels are stubbed and filled out in Task 11.
  """
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.VerificationTask
  alias Showcase.Planogram.VisionPipeline
  alias ShowcaseWeb.Planogram.Components.QRHandoff

  import QRHandoff

  @roles ~w(merchandiser manager admin)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      for task <- Planogram.list_tasks() do
        Phoenix.PubSub.subscribe(Showcase.PubSub, VisionPipeline.topic(task.id))
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "Planogram Manager")
     |> assign(:role, "merchandiser")
     |> assign(:active_qr_task_id, nil)
     |> assign(:planograms, Planogram.list_planograms())
     |> assign(:new_planogram, %{"name" => "", "description" => ""})
     |> allow_upload(:reference,
       accept: ~w(.png .jpg .jpeg),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> load_tasks()}
  end

  defp load_tasks(socket) do
    today = Date.utc_today()
    buckets = Planogram.bucket_tasks(today)
    assign(socket, buckets: buckets, today: today)
  end

  @impl true
  def handle_event("switch_role", %{"role" => role}, socket) when role in @roles do
    {:noreply, assign(socket, role: role)}
  end

  def handle_event("run_analysis", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    Planogram.enqueue_analysis(id)
    {:noreply, socket |> put_flash(:info, "Analysis enqueued.") |> load_tasks()}
  end

  def handle_event("toggle_qr", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    new_active = if socket.assigns.active_qr_task_id == id, do: nil, else: id
    {:noreply, assign(socket, active_qr_task_id: new_active)}
  end

  def handle_event("create_task", %{"task" => task_attrs}, socket) do
    # Scenario is meaningless when running against real Claude; default to
    # "compliant" so the existing changeset validation passes.
    task_attrs = Map.put_new(task_attrs, "scenario", "compliant")

    case Planogram.create_task(task_attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created.")
         |> assign(:planograms, Planogram.list_planograms())
         |> load_tasks()}

      {:error, changeset} ->
        require Logger
        Logger.error("create_task failed: #{inspect(changeset.errors)}")
        msg = "Could not create task: #{format_changeset_errors(changeset)}"
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("delete_task", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)

    case Planogram.delete_task(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task deleted.")
         |> load_tasks()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete task: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_planogram", %{"planogram_id" => pg_id}, socket) do
    {id, _} = Integer.parse(pg_id)

    case Planogram.delete_planogram(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Planogram deleted (and all its tasks).")
         |> assign(:planograms, Planogram.list_planograms())
         |> load_tasks()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not delete planogram: #{inspect(reason)}")}
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  def handle_event("validate_planogram", %{"planogram" => attrs}, socket) do
    # Persist typed name/description across upload-progress re-renders so the
    # inputs don't reset when the user picks a file.
    {:noreply, assign(socket, :new_planogram, attrs)}
  end

  def handle_event("validate_planogram", _params, socket), do: {:noreply, socket}

  def handle_event("create_planogram", %{"planogram" => attrs}, socket) do
    uploaded =
      consume_uploaded_entries(socket, :reference, fn %{path: tmp}, _entry ->
        {:ok, File.read!(tmp)}
      end)

    case uploaded do
      [bytes] ->
        case Planogram.create_planogram_with_reference(attrs, bytes) do
          {:ok, _pg} ->
            {:noreply,
             socket
             |> put_flash(:info, "Planogram added.")
             |> assign(:planograms, Planogram.list_planograms())
             |> assign(:new_planogram, %{"name" => "", "description" => ""})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not save planogram.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Please attach a reference image.")}
    end
  end

  @impl true
  def handle_info({:planogram, _phase, _task_id}, socket) do
    {:noreply, load_tasks(socket)}
  end

  def handle_info({:planogram, :task_failed, _task_id, _reason}, socket) do
    {:noreply, load_tasks(socket)}
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
            <button
              :for={role <- ~w(merchandiser manager admin)}
              type="button"
              phx-click="switch_role"
              phx-value-role={role}
              class={[
                "rounded px-3 py-2 text-sm font-medium transition-colors",
                if(@role == role,
                  do: "bg-ink text-white",
                  else: "bg-white border border-line text-ink/80 hover:bg-surface-lav"
                )
              ]}
            >
              {String.capitalize(role)}
            </button>
            <a href="/" class="ml-2 text-sm text-ink/60 hover:text-purple transition-colors">
              &larr; Dashboard
            </a>
          </div>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-7xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Neurony · Planogram Manager
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            {role_title(@role)}
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            {role_subtitle(@role)}
          </p>
        </div>
      </div>

      <main class="max-w-7xl mx-auto px-6 py-6">
        <div :if={@flash["info"]} class="mb-4 rounded-2xl border border-emerald-200 bg-emerald-50 shadow-sm px-4 py-2 text-sm text-emerald-800">
          {@flash["info"]}
        </div>
        <div :if={@flash["error"]} class="mb-4 rounded-2xl border border-rose-200 bg-rose-50 shadow-sm px-4 py-2 text-sm text-rose-800">
          {@flash["error"]}
        </div>

        <%= case @role do %>
          <% "merchandiser" -> %>
            <.render_merchandiser buckets={@buckets} active_qr_task_id={@active_qr_task_id} />
          <% "manager" -> %>
            <.render_manager
              planograms={@planograms}
              uploads={@uploads}
              buckets={@buckets}
              new_planogram={@new_planogram}
            />
          <% "admin" -> %>
            <.render_admin />
        <% end %>
      </main>
    </div>
    """
  end

  defp role_subtitle("merchandiser"),
    do: "Today's audits — capture photo, run AI compliance check."

  defp role_subtitle("manager"), do: "Author planograms and create verification tasks."
  defp role_subtitle("admin"), do: "Audit log, model settings, cost overview."

  defp role_title("merchandiser"), do: "Field audits"
  defp role_title("manager"), do: "Manage planograms and tasks"
  defp role_title("admin"), do: "Admin overview"

  attr :buckets, :map, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp render_merchandiser(assigns) do
    ~H"""
    <div class="space-y-6">
      <.task_bucket
        label="Overdue"
        tasks={@buckets.overdue}
        tone="rose"
        active_qr_task_id={@active_qr_task_id}
      />
      <.task_bucket
        label="Today"
        tasks={@buckets.today}
        tone="emerald"
        active_qr_task_id={@active_qr_task_id}
      />
      <.task_bucket
        label="Tomorrow"
        tasks={@buckets.tomorrow}
        tone="amber"
        active_qr_task_id={@active_qr_task_id}
      />
      <.task_bucket
        label="Later"
        tasks={@buckets.later}
        tone="zinc"
        active_qr_task_id={@active_qr_task_id}
      />
      <.task_bucket
        label="Done"
        tasks={@buckets.done}
        tone="zinc"
        active_qr_task_id={@active_qr_task_id}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tasks, :list, required: true
  attr :tone, :string, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp task_bucket(assigns) do
    ~H"""
    <section :if={@tasks != []} class="rounded-2xl border border-line bg-white shadow-sm overflow-hidden">
      <header class={[
        "border-b border-line px-5 py-3 text-xs uppercase tracking-wider font-semibold",
        "text-#{@tone}-700 bg-#{@tone}-50"
      ]}>
        {@label} ({length(@tasks)})
      </header>
      <ul class="divide-y divide-line">
        <li :for={task <- @tasks} class="p-5">
          <.task_row task={task} active_qr_task_id={@active_qr_task_id} />
        </li>
      </ul>
    </section>
    """
  end

  attr :task, VerificationTask, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp task_row(assigns) do
    score =
      case assigns.task.result do
        %{"compliance_score" => s} when is_number(s) -> s
        _ -> nil
      end

    assigns = assign(assigns, :score, score)

    ~H"""
    <div class="flex items-center justify-between gap-4">
      <div class="flex-1">
        <div class="flex items-center gap-3 flex-wrap">
          <a href={"/planogram/#{@task.id}"} class="font-medium text-ink hover:underline">
            {@task.store_name}
          </a>
          <span :if={@score} class={[
            "rounded-full px-2.5 py-0.5 text-xs font-bold",
            score_pill_classes(@score)
          ]}>
            {@score}%
          </span>
          <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
            {@task.status}
          </span>
        </div>
        <div class="text-xs text-ink/60 mt-1">
          Due {Date.to_iso8601(@task.due_date)} · {@task.planogram && @task.planogram.name}
        </div>
      </div>

      <div class="flex items-center gap-2">
        <a
          :if={@task.status == "complete"}
          href={"/planogram/#{@task.id}"}
          class="rounded-lg bg-purple px-3 py-2 text-sm font-semibold text-white hover:opacity-90"
        >
          View results
        </a>
        <button
          :if={@task.status != "complete"}
          type="button"
          phx-click="run_analysis"
          phx-value-task_id={@task.id}
          disabled={@task.status == "analyzing"}
          class="rounded-lg bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-40"
        >
          Run analysis
        </button>
        <button
          type="button"
          phx-click="toggle_qr"
          phx-value-task_id={@task.id}
          class="rounded-lg border border-line px-3 py-2 text-sm text-ink/80 hover:bg-surface-lav"
        >
          {if @active_qr_task_id == @task.id, do: "Hide QR", else: "Open on phone"}
        </button>
      </div>
    </div>

    <div :if={@active_qr_task_id == @task.id} class="mt-4">
      <.qr_handoff url={qr_url(@task)} />
    </div>
    """
  end

  defp score_pill_classes(s) when is_number(s) and s >= 90, do: "bg-emerald-100 text-emerald-800"
  defp score_pill_classes(s) when is_number(s) and s >= 60, do: "bg-amber-100 text-amber-800"
  defp score_pill_classes(_), do: "bg-rose-100 text-rose-800"

  defp qr_url(task) do
    host = ShowcaseWeb.Endpoint.config(:url)[:host] || "localhost"
    port = (ShowcaseWeb.Endpoint.config(:http) || [])[:port] || 4321
    "http://#{host}:#{port}/planogram/mobile/#{task.mobile_token}"
  end

  defp status_classes("pending"), do: "bg-surface-lav text-ink/80"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-surface-lav"

  attr :planograms, :list, required: true
  attr :uploads, :map, required: true
  attr :buckets, :map, required: true
  attr :new_planogram, :map, required: true

  defp render_manager(assigns) do
    all_tasks =
      [
        assigns.buckets.overdue,
        assigns.buckets.today,
        assigns.buckets.tomorrow,
        assigns.buckets.later,
        assigns.buckets.done
      ]
      |> List.flatten()

    assigns = assign(assigns, :all_tasks, all_tasks)

    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
          <h2 class="text-lg font-medium mb-3">Existing planograms</h2>
          <ul :if={@planograms != []} class="divide-y">
            <li :for={pg <- @planograms} class="py-2 flex gap-3 items-start">
              <img
                :if={pg.reference_image_path}
                src={pg.reference_image_path}
                alt={pg.name}
                class="w-12 h-12 object-cover rounded-lg border border-line bg-surface-lav-2 flex-shrink-0"
              />
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{pg.name}</div>
                <div class="text-xs text-ink/60 truncate">{pg.description}</div>
              </div>
              <button
                type="button"
                phx-click="delete_planogram"
                phx-value-planogram_id={pg.id}
                data-confirm={"Delete planogram \"#{pg.name}\" and all its tasks?"}
                class="text-xs text-rose-600 hover:text-rose-800 underline flex-shrink-0"
              >
                Delete
              </button>
            </li>
          </ul>
          <p :if={@planograms == []} class="text-sm text-ink/60">
            No planograms yet — upload one on the right.
          </p>
        </section>

        <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
          <h2 class="text-lg font-medium mb-3">Add planogram</h2>
          <form
            phx-submit="create_planogram"
            phx-change="validate_planogram"
            class="space-y-3"
          >
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Name</label>
              <input
                name="planogram[name]"
                value={@new_planogram["name"] || ""}
                required
                class="w-full rounded-lg border border-line px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Description</label>
              <textarea
                name="planogram[description]"
                rows="2"
                class="w-full rounded-lg border border-line px-3 py-2"
              >{@new_planogram["description"] || ""}</textarea>
            </div>
            <div>
              <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">
                Reference image
              </label>
              <.live_file_input upload={@uploads.reference} class="block w-full text-sm" />
              <div
                :for={entry <- @uploads.reference.entries}
                class="text-xs text-ink/70 mt-1"
              >
                {entry.client_name} — {entry.progress}%
                <div
                  :for={err <- upload_errors(@uploads.reference, entry)}
                  class="text-rose-600"
                >
                  {upload_error_to_string(err)}
                </div>
              </div>
              <p class="text-xs text-ink/50 mt-1">PNG/JPEG, max 5 MB.</p>
            </div>
            <button
              type="submit"
              disabled={@uploads.reference.entries == []}
              class="w-full rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Save planogram
            </button>
            <p :if={@uploads.reference.entries == []} class="text-xs text-ink/60 mt-1">
              Attach a reference image to enable save.
            </p>
          </form>
        </section>
      </div>

      <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
        <h2 class="text-lg font-medium mb-3">Create task</h2>
        <p :if={@planograms == []} class="text-sm text-rose-700 mb-3">
          Add a planogram first.
        </p>
        <form :if={@planograms != []} phx-submit="create_task" class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
          <div>
            <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Store</label>
            <input
              name="task[store_name]"
              required
              class="w-full rounded-lg border border-line px-3 py-2"
              placeholder="e.g. Bucharest Mall"
            />
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Planogram</label>
            <select name="task[planogram_id]" required class="w-full rounded-lg border border-line px-3 py-2">
              <option :for={pg <- @planograms} value={pg.id}>{pg.name}</option>
            </select>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-ink/60 mb-1">Due date</label>
            <input
              name="task[due_date]"
              type="date"
              required
              class="w-full rounded-lg border border-line px-3 py-2"
            />
          </div>
          <div class="md:col-span-3">
            <button
              type="submit"
              class="w-full md:w-auto rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90"
            >
              Create task
            </button>
          </div>
        </form>
      </section>

      <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
        <h2 class="text-lg font-medium mb-3">All tasks ({length(@all_tasks)})</h2>
        <p :if={@all_tasks == []} class="text-sm text-ink/60">
          No tasks yet — create one above.
        </p>
        <table :if={@all_tasks != []} class="w-full text-sm">
          <thead class="text-xs uppercase tracking-wide text-ink/60">
            <tr>
              <th class="text-left py-2">Store</th>
              <th class="text-left py-2">Planogram</th>
              <th class="text-left py-2">Due</th>
              <th class="text-left py-2">Status</th>
              <th class="text-right py-2">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={task <- @all_tasks}>
              <td class="py-2 font-medium">{task.store_name}</td>
              <td class="py-2 text-ink/70">
                {task.planogram && task.planogram.name}
              </td>
              <td class="py-2 text-ink/70">{task.due_date}</td>
              <td class="py-2">
                <span class={["rounded px-2 py-0.5 text-xs", status_classes(task.status)]}>
                  {task.status}
                </span>
              </td>
              <td class="py-2 text-right space-x-3">
                <a href={"/planogram/#{task.id}"} class="text-xs text-ink/80 underline hover:text-ink">
                  Open
                </a>
                <button
                  type="button"
                  phx-click="delete_task"
                  phx-value-task_id={task.id}
                  data-confirm={"Delete task \"#{task.store_name}\"?"}
                  class="text-xs text-rose-600 hover:text-rose-800 underline"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 5 MB)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported file type (.png, .jpg)."
  defp upload_error_to_string(:too_many_files), do: "Only one file allowed."
  defp upload_error_to_string(_), do: "Upload error."

  defp render_admin(assigns) do
    ~H"""
    <section class="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <h2 class="text-lg font-medium mb-3">Admin overview</h2>
      <dl class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <dt class="text-xs uppercase tracking-wide text-ink/60">Vision model</dt>
          <dd class="font-mono">claude-sonnet-4-5 (pinned)</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-ink/60">Default text model</dt>
          <dd class="font-mono">{Showcase.Common.Config.default_model()}</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-ink/60">Oban queue</dt>
          <dd class="font-mono">:planogram (concurrency 5)</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-ink/60">Fingerprint</dt>
          <dd class="font-mono">planogram_vision_v1</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-ink/60">Scenarios</dt>
          <dd class="font-mono">compliant / minor_issues / major_issues</dd>
        </div>
      </dl>
      <p class="mt-4 text-xs text-ink/60">
        Reset all data and audit log via <a href="/admin/reset" class="underline">/admin/reset</a>.
      </p>
    </section>
    """
  end
end
