defmodule ShowcaseWeb.Admin.AuditLogLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.AuditLog

  @page_size 50

  @impl true
  def mount(params, _session, socket) do
    demo = Map.get(params, "demo")

    {:ok,
     socket
     |> assign(:page_size, @page_size)
     |> assign(:demo_filter, demo)
     |> assign(:entries, load_entries(demo))
     |> assign(:demos, distinct_demos())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    demo = Map.get(params, "demo")

    {:noreply,
     socket
     |> assign(:demo_filter, demo)
     |> assign(:entries, load_entries(demo))}
  end

  defp load_entries(demo) do
    # Filter + sort + limit pushed to the DB (Ash :list_recent action),
    # backed by an index on (demo, inserted_at). See REVIEW.md MED-02.
    AuditLog.list_recent!(%{demo: demo, limit: @page_size})
  end

  defp distinct_demos do
    AuditLog
    |> Ash.read!()
    |> Enum.map(& &1.demo)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Audit log</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Append-only event log. Newest first. Showing up to {@page_size} entries.
            </p>
          </div>
          <a href="/admin/reset" class="text-sm text-zinc-500 underline">Admin home</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-6">
        <nav class="mb-4 flex gap-2 items-center flex-wrap">
          <span class="text-xs uppercase tracking-wide text-zinc-500">Filter:</span>
          <a
            href="/admin/audit-log"
            class={[
              "rounded px-2 py-1 text-xs",
              if(@demo_filter == nil, do: "bg-zinc-900 text-white", else: "bg-white border")
            ]}
          >
            All
          </a>
          <a
            :for={demo <- @demos}
            href={"/admin/audit-log?demo=#{demo}"}
            class={[
              "rounded px-2 py-1 text-xs",
              if(@demo_filter == demo, do: "bg-zinc-900 text-white", else: "bg-white border")
            ]}
          >
            {demo}
          </a>
        </nav>

        <p
          :if={@entries == []}
          class="rounded border bg-white p-6 text-center text-sm text-zinc-500"
        >
          No audit entries yet.
        </p>

        <ol :if={@entries != []} class="rounded border bg-white divide-y">
          <li :for={entry <- @entries} class="px-4 py-3 flex gap-4 items-start">
            <div class="w-40 shrink-0 text-xs text-zinc-500 font-mono">
              {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M:%S")}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span class="rounded bg-zinc-100 px-2 py-0.5 text-xs">{entry.demo}</span>
                <span class="text-xs text-zinc-600">
                  {entry.entity_type} #{entry.entity_id}
                </span>
                <span class="font-medium">{entry.event}</span>
                <span :if={entry.actor} class="text-xs text-zinc-400">by {entry.actor}</span>
              </div>
              <pre
                :if={entry.payload != %{}}
                class="bg-zinc-50 text-xs p-2 rounded overflow-x-auto"
              ><%= Jason.encode!(entry.payload, pretty: true) %></pre>
            </div>
          </li>
        </ol>
      </main>
    </div>
    """
  end
end
