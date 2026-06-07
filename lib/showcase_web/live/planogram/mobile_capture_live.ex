defmodule ShowcaseWeb.Planogram.MobileCaptureLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.MobileHandoff
  alias Showcase.Repo

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case MobileHandoff.find_task_by_token(token) do
      {:ok, task} ->
        task = Repo.preload(task, :planogram)

        socket =
          socket
          |> assign(:task, task)
          |> assign(:error, nil)
          |> allow_upload(:photo,
            accept: ~w(.png .jpg .jpeg),
            max_entries: 1,
            max_file_size: 8_000_000
          )

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, assign(socket, task: nil, error: :not_found)}

      {:error, :already_processed} ->
        {:ok, assign(socket, task: nil, error: :already_processed)}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("submit", _params, socket) do
    [_entry | _] = socket.assigns.uploads.photo.entries

    consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, _entry ->
      bytes = File.read!(tmp_path)
      {:ok, updated} = MobileHandoff.finalize_upload(socket.assigns.task, bytes)
      Planogram.enqueue_analysis(updated.id)
      {:ok, updated}
    end)

    {:noreply,
     socket
     |> assign(:task, Planogram.get_task!(socket.assigns.task.id))
     |> put_flash(:info, "Photo uploaded — analysis enqueued. You can close this tab.")}
  end

  @impl true
  def render(%{error: :not_found} = assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-6 bg-surface-lav-2">
      <div class="rounded border bg-white p-6 max-w-md text-center">
        <h1 class="text-lg font-semibold mb-2">Link is no longer valid</h1>
        <p class="text-sm text-ink/70">
          The mobile-capture link could not be matched to a verification task.
        </p>
      </div>
    </div>
    """
  end

  def render(%{error: :already_processed} = assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-6 bg-surface-lav-2">
      <div class="rounded border bg-white p-6 max-w-md text-center">
        <h1 class="text-lg font-semibold mb-2">Already done</h1>
        <p class="text-sm text-ink/70">
          This audit has already been processed. Switch back to the desktop view.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="bg-white border-b border-line px-4 py-4">
        <img src={~p"/images/neurony/wordmark.svg"} class="h-6" alt="Neurony" />
      </header>

      <div class="px-4 py-6">
        <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
          Mobile capture
        </p>
        <h1 class="mt-2 font-heading font-bold text-2xl text-ink tracking-tight">
          {@task.store_name}
        </h1>
        <p class="mt-1 font-body text-sm text-ink/60">{@task.planogram.name}</p>

        <form phx-submit="submit" phx-change="validate" class="mt-6 space-y-4">
          <label class="block">
            <span class="block text-sm font-medium text-ink mb-2">Capture photo</span>
            <.live_file_input upload={@uploads.photo} class="w-full" />
          </label>

          <div :for={entry <- @uploads.photo.entries} class="text-sm text-ink/70">
            {entry.client_name} — {entry.progress}%
            <div :for={err <- upload_errors(@uploads.photo, entry)} class="text-rose-600 text-xs">
              {error_to_string(err)}
            </div>
          </div>

          <button
            type="submit"
            disabled={@uploads.photo.entries == []}
            class="w-full rounded bg-purple px-4 py-3 text-base font-semibold text-white hover:opacity-90 disabled:opacity-40"
          >
            Upload &amp; analyze
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "Photo is too large (max 8 MB)."
  defp error_to_string(:not_accepted), do: "Not a supported file type (.png, .jpg)."
  defp error_to_string(_), do: "Upload error."
end
