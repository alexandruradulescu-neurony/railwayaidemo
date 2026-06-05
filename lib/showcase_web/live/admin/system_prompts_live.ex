defmodule ShowcaseWeb.Admin.SystemPromptsLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.SystemPrompt

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :groups, load_groups())}
  end

  defp load_groups do
    SystemPrompt
    |> Ash.read!()
    |> Enum.group_by(& &1.demo)
    |> Enum.map(fn {demo, prompts} ->
      # Keep only the latest version per section
      latest_per_section =
        prompts
        |> Enum.group_by(& &1.section)
        |> Enum.map(fn {_section, versions} ->
          Enum.max_by(versions, & &1.version)
        end)
        |> Enum.sort_by(& &1.section)

      {demo, latest_per_section}
    end)
    |> Enum.sort_by(fn {demo, _} -> demo end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">System prompts</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Read-only view of the active system prompts per demo. To edit, change the
              source module and re-seed (the seeder versions new bodies automatically).
            </p>
          </div>
          <a href="/admin/reset" class="text-sm text-zinc-500 underline">Admin home</a>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-6 py-6 space-y-8">
        <section :for={{demo, prompts} <- @groups} class="rounded border bg-white">
          <header class="border-b px-4 py-3">
            <h2 class="text-lg font-semibold">{demo}</h2>
            <p class="text-xs text-zinc-500">{length(prompts)} active section(s)</p>
          </header>
          <div class="divide-y">
            <article :for={p <- prompts} class="px-4 py-4">
              <div class="flex items-center justify-between mb-2">
                <div>
                  <h3 class="font-medium">{p.section}</h3>
                  <p :if={p.note} class="text-xs text-zinc-500">{p.note}</p>
                </div>
                <div class="text-xs text-zinc-400">
                  v{p.version} · updated {Calendar.strftime(p.updated_at, "%Y-%m-%d %H:%M")}
                </div>
              </div>
              <pre class="bg-zinc-50 text-xs p-3 rounded whitespace-pre-wrap break-words">{p.body}</pre>
            </article>
          </div>
        </section>

        <p
          :if={@groups == []}
          class="rounded border bg-white p-6 text-center text-sm text-zinc-500"
        >
          No system prompts seeded yet. Run <code>mix ecto.reset</code> and re-seed.
        </p>
      </main>
    </div>
    """
  end
end
