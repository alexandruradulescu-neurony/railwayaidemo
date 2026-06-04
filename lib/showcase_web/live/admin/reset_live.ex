defmodule ShowcaseWeb.Admin.ResetLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.Reset
  alias Showcase.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset (admin)")
     |> assign(:live_tiles, Dashboard.live_tiles())
     |> assign(:last_action, nil)
     |> assign(:last_action_at, nil)}
  end

  @impl true
  def handle_event("reset_all", _params, socket) do
    case Reset.run(Dashboard.live_seeders()) do
      :ok ->
        {:noreply,
         socket
         |> assign(:last_action, "all demos")
         |> assign(:last_action_at, DateTime.utc_now())
         |> put_flash(:info, "All live demos reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reset_demo", %{"id" => id_string}, socket) do
    id = String.to_existing_atom(id_string)

    case Dashboard.find_tile(id) do
      %{seeder: seeder} = tile when not is_nil(seeder) ->
        case Reset.run([seeder]) do
          :ok ->
            {:noreply,
             socket
             |> assign(:last_action, tile.title)
             |> assign(:last_action_at, DateTime.utc_now())
             |> put_flash(:info, "#{tile.title} reset.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "#{tile.title} reset failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Unknown demo: #{id_string}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl">
      <h1 class="text-xl font-semibold">Reset demo data</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Per-demo resets TRUNCATE that demo's tables + re-seed inside a transaction.
        In-flight Oban jobs on the demo's queue are cancelled first.
      </p>

      <div class="mt-6">
        <button
          type="button"
          class="rounded bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700"
          phx-click="reset_all"
          data-confirm="Reset ALL demos? This wipes all demo data."
        >
          Reset all demos
        </button>
      </div>

      <div class="mt-6">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Per-demo reset</h2>
        <ul class="space-y-2">
          <li :for={tile <- @live_tiles} class="flex items-center justify-between gap-4 border rounded p-3">
            <div>
              <p class="font-medium text-sm">{tile.title}</p>
              <p class="text-xs text-zinc-500">{tile.description}</p>
            </div>
            <button
              type="button"
              class="rounded bg-zinc-200 px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-300"
              phx-click="reset_demo"
              phx-value-id={tile.id}
              data-confirm={"Reset #{tile.title}? Wipes this demo's data."}
            >
              Reset {tile.title}
            </button>
          </li>
        </ul>
      </div>

      <%= if @last_action do %>
        <p class="text-xs text-zinc-500 mt-6">
          Last reset: <span class="font-mono">{@last_action}</span>
          at <span class="font-mono">{@last_action_at}</span>
        </p>
      <% end %>
    </div>
    """
  end
end
