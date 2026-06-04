defmodule ShowcaseWeb.Admin.ResetLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.Reset

  @seeders [Showcase.OrderFlow.Seed]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset (admin)")
     |> assign(:last_reset_at, nil)}
  end

  @impl true
  def handle_event("reset_all", _params, socket) do
    case Reset.run(@seeders) do
      :ok ->
        {:noreply,
         socket
         |> assign(:last_reset_at, DateTime.utc_now())
         |> put_flash(:info, "Demos reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-2xl">
      <h1 class="text-xl font-semibold">Reset demo data</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Click to TRUNCATE per-demo tables + re-seed. Resets in-flight Oban jobs first.
      </p>

      <button
        type="button"
        class="mt-4 rounded bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700"
        phx-click="reset_all"
        data-confirm="Reset all demos? This wipes demo data."
      >
        Reset OrderFlow
      </button>

      <%= if @last_reset_at do %>
        <p class="text-xs text-zinc-500 mt-3">Last reset: <span class="font-mono">{@last_reset_at}</span></p>
      <% end %>
    </div>
    """
  end
end
