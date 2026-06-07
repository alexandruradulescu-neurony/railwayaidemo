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

  def handle_event("force_truncation", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    Planogram.enqueue_analysis(id, max_tokens: 200)

    {:noreply,
     socket
     |> put_flash(:info, "Truncated analysis enqueued (max_tokens=200).")
     |> load_tasks()}
  end

  def handle_event("toggle_qr", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    new_active = if socket.assigns.active_qr_task_id == id, do: nil, else: id
    {:noreply, assign(socket, active_qr_task_id: new_active)}
  end

  def handle_event("create_task", %{"task" => task_attrs}, socket) do
    case Planogram.create_task(task_attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created.")
         |> assign(:planograms, Planogram.list_planograms())
         |> load_tasks()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create task.")}
    end
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
             |> assign(:planograms, Planogram.list_planograms())}

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
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Planogram Manager</h1>
            <p class="text-sm text-zinc-500 mt-1">
              {role_subtitle(@role)}
            </p>
          </div>
          <div class="flex gap-2 items-center">
            <button
              :for={role <- ~w(merchandiser manager admin)}
              type="button"
              phx-click="switch_role"
              phx-value-role={role}
              class={[
                "rounded px-3 py-2 text-sm font-medium",
                if(@role == role,
                  do: "bg-zinc-900 text-white",
                  else: "bg-white border text-zinc-700 hover:bg-zinc-100"
                )
              ]}
            >
              {String.capitalize(role)}
            </button>
            <a href="/" class="ml-2 text-sm text-zinc-500 underline">&larr; Dashboard</a>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-6">
        <%= case @role do %>
          <% "merchandiser" -> %>
            <.render_merchandiser buckets={@buckets} active_qr_task_id={@active_qr_task_id} />
          <% "manager" -> %>
            <.render_manager planograms={@planograms} uploads={@uploads} />
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
    <section :if={@tasks != []} class="rounded border bg-white">
      <header class={[
        "border-b px-4 py-2 text-xs uppercase tracking-wide",
        "text-#{@tone}-700 bg-#{@tone}-50"
      ]}>
        {@label} ({length(@tasks)})
      </header>
      <ul class="divide-y">
        <li :for={task <- @tasks} class="p-4">
          <.task_row task={task} active_qr_task_id={@active_qr_task_id} />
        </li>
      </ul>
    </section>
    """
  end

  attr :task, VerificationTask, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp task_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <div class="flex-1">
        <div class="flex items-center gap-3">
          <a href={"/planogram/#{@task.id}"} class="font-medium hover:underline">
            {@task.store_name}
          </a>
          <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
            {@task.status}
          </span>
        </div>
        <div class="text-xs text-zinc-500 mt-1">
          Due {Date.to_iso8601(@task.due_date)} · {@task.planogram && @task.planogram.name} · scenario: {@task.scenario}
        </div>
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="run_analysis"
          phx-value-task_id={@task.id}
          disabled={@task.status in ["analyzing", "complete"]}
          class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-40"
        >
          Run analysis
        </button>
        <button
          type="button"
          phx-click="force_truncation"
          phx-value-task_id={@task.id}
          title="Cap max_tokens=200 to demo the resilient parser"
          class="rounded border px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100"
        >
          Force truncation
        </button>
        <button
          type="button"
          phx-click="toggle_qr"
          phx-value-task_id={@task.id}
          class="rounded border px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100"
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

  defp qr_url(task) do
    host = ShowcaseWeb.Endpoint.config(:url)[:host] || "localhost"
    port = (ShowcaseWeb.Endpoint.config(:http) || [])[:port] || 4321
    "http://#{host}:#{port}/planogram/mobile/#{task.mobile_token}"
  end

  defp status_classes("pending"), do: "bg-zinc-100 text-zinc-700"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-zinc-100"

  attr :planograms, :list, required: true
  attr :uploads, :map, required: true

  defp render_manager(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <section class="rounded border bg-white p-4">
        <h2 class="text-lg font-medium mb-3">Existing planograms</h2>
        <ul :if={@planograms != []} class="divide-y">
          <li :for={pg <- @planograms} class="py-2 flex gap-3 items-start">
            <img
              :if={pg.reference_image_path}
              src={pg.reference_image_path}
              alt={pg.name}
              class="w-12 h-12 object-cover rounded border bg-zinc-50 flex-shrink-0"
            />
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{pg.name}</div>
              <div class="text-xs text-zinc-500 truncate">{pg.description}</div>
            </div>
          </li>
        </ul>
        <p :if={@planograms == []} class="text-sm text-zinc-500">
          No planograms yet — upload one on the right.
        </p>
      </section>

      <section class="rounded border bg-white p-4">
        <h2 class="text-lg font-medium mb-3">Add planogram</h2>
        <form
          phx-submit="create_planogram"
          phx-change="validate_planogram"
          class="space-y-3"
        >
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Name</label>
            <input name="planogram[name]" required class="w-full rounded border px-3 py-2" />
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Description</label>
            <textarea
              name="planogram[description]"
              rows="2"
              class="w-full rounded border px-3 py-2"
            ></textarea>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">
              Reference image
            </label>
            <.live_file_input upload={@uploads.reference} class="block w-full text-sm" />
            <div
              :for={entry <- @uploads.reference.entries}
              class="text-xs text-zinc-600 mt-1"
            >
              {entry.client_name} — {entry.progress}%
              <div
                :for={err <- upload_errors(@uploads.reference, entry)}
                class="text-rose-600"
              >
                {upload_error_to_string(err)}
              </div>
            </div>
            <p class="text-xs text-zinc-400 mt-1">PNG/JPEG, max 5 MB.</p>
          </div>
          <button
            type="submit"
            disabled={@uploads.reference.entries == []}
            class="w-full rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Save planogram
          </button>
          <p :if={@uploads.reference.entries == []} class="text-xs text-zinc-500 mt-1">
            Attach a reference image to enable save.
          </p>
        </form>
      </section>

      <section class="rounded border bg-white p-4">
        <h2 class="text-lg font-medium mb-3">Create task</h2>
        <form phx-submit="create_task" class="space-y-3">
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Store</label>
            <input name="task[store_name]" required class="w-full rounded border px-3 py-2" />
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Planogram</label>
            <select name="task[planogram_id]" class="w-full rounded border px-3 py-2">
              <option :for={pg <- @planograms} value={pg.id}>{pg.name}</option>
            </select>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Due date</label>
            <input name="task[due_date]" type="date" required class="w-full rounded border px-3 py-2" />
            <p class="mt-1 text-xs text-zinc-400">Past dates allowed (demo overdue treatment).</p>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Scenario</label>
            <select name="task[scenario]" class="w-full rounded border px-3 py-2">
              <option value="compliant">compliant</option>
              <option value="minor_issues">minor_issues</option>
              <option value="major_issues">major_issues</option>
            </select>
          </div>
          <button
            type="submit"
            class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
          >
            Create task
          </button>
        </form>
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
    <section class="rounded border bg-white p-4">
      <h2 class="text-lg font-medium mb-3">Admin overview</h2>
      <dl class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Vision model</dt>
          <dd class="font-mono">claude-sonnet-4-5 (pinned)</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Default text model</dt>
          <dd class="font-mono">{Showcase.Common.Config.default_model()}</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Oban queue</dt>
          <dd class="font-mono">:planogram (concurrency 5)</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Fingerprint</dt>
          <dd class="font-mono">planogram_vision_v1</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Scenarios</dt>
          <dd class="font-mono">compliant / minor_issues / major_issues</dd>
        </div>
      </dl>
      <p class="mt-4 text-xs text-zinc-500">
        Reset all data and audit log via <a href="/admin/reset" class="underline">/admin/reset</a>.
      </p>
    </section>
    """
  end
end
