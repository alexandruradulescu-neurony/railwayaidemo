defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.{MockPrompts, PhoneScreenPipeline}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    app = RecruitFlow.find_application(String.to_integer(id))

    if app == nil do
      {:ok, push_navigate(socket, to: "/recruit-flow")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")
      end

      {:ok, socket |> assign_app(app) |> assign(:phone_scenarios, MockPrompts.phone_scenarios())}
    end
  end

  defp assign_app(socket, app) do
    {:ok, audits} = AuditLog.for_entity("recruit_flow", "application", to_string(app.id))

    socket
    |> assign(:page_title, "Application ##{app.id}")
    |> assign(:app, app)
    |> assign(:audit, audits)
  end

  @impl true
  def handle_event("run_ai_screen", %{"scenario" => scenario}, socket) do
    case PhoneScreenPipeline.run(socket.assigns.app, %{now: DateTime.utc_now(), scenario: scenario}) do
      {:ok, _} ->
        app = RecruitFlow.find_application(socket.assigns.app.id)
        {:noreply, socket |> assign_app(app) |> put_flash(:info, "Phone screen complete.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Phone screen failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:recruit_flow, :transitioned, %{application_id: id}}, socket)
      when id == socket.assigns.app.id do
    {:noreply, assign_app(socket, RecruitFlow.find_application(id))}
  end

  def handle_info({:recruit_flow, _, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/recruit-flow" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Board
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-5xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Candidate · {@app.position && @app.position.title}
          </p>
          <div class="mt-2 flex items-baseline gap-3 flex-wrap">
            <h1 class="font-heading font-bold text-3xl text-ink tracking-tight">
              {@app.candidate.name}
            </h1>
            <span class="font-mono text-sm text-ink/60">{@app.state}</span>
          </div>
        </div>
      </div>

      <main class="max-w-5xl mx-auto px-6 py-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section class="lg:col-span-2 space-y-4">
          <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
            <h2 class="text-sm uppercase tracking-wide text-ink/60 mb-2">Transcript</h2>
            <%= if @app.transcript do %>
              <pre class="whitespace-pre-wrap text-sm text-ink/80">{@app.transcript}</pre>
            <% else %>
              <p class="text-sm text-ink/60">No transcript yet.</p>
            <% end %>
          </div>

          <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
            <h2 class="text-sm uppercase tracking-wide text-ink/60 mb-2">Eval</h2>
            <%= if @app.eval not in [nil, %{}] do %>
              <p class="text-sm">outcome: <span class="font-mono">{@app.eval["outcome"]}</span></p>
              <p class="text-sm">score: <span class="font-mono">{@app.eval["score"]}</span></p>
              <p class="text-sm mt-2 text-ink/80">{@app.eval["reasoning"]}</p>
            <% else %>
              <p class="text-sm text-ink/60">No eval yet.</p>
            <% end %>
          </div>
        </section>

        <aside class="space-y-4">
          <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
            <h2 class="text-sm uppercase tracking-wide text-ink/60 mb-2">Run AI screen</h2>
            <div class="flex flex-col gap-2">
              <button
                :for={s <- @phone_scenarios}
                type="button"
                class="text-xs underline text-emerald-700 text-left"
                phx-click="run_ai_screen"
                phx-value-scenario={s.name}
              >
                {s.name}
              </button>
            </div>
          </div>

          <div class="rounded-2xl border border-line bg-white p-6 shadow-sm">
            <h2 class="text-sm uppercase tracking-wide text-ink/60 mb-2">Transition timeline</h2>
            <%= if @audit == [] do %>
              <p class="text-sm text-ink/60">No transitions yet.</p>
            <% else %>
              <ol class="space-y-2">
                <li :for={entry <- @audit} class="text-xs border-l-2 border-line pl-2">
                  <p class="font-medium">{entry.event}</p>
                  <p class="text-ink/60">{entry.payload["from"]} → {entry.payload["to"]}</p>
                  <p class="text-ink/50">{entry.inserted_at}</p>
                </li>
              </ol>
            <% end %>
          </div>
        </aside>
      </main>
    </div>
    """
  end
end
