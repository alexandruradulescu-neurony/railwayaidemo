defmodule ShowcaseWeb.RecruitFlow.KanbanLive do
  use ShowcaseWeb, :live_view

  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.{CvMatcher, MockPrompts, PhoneScreenPipeline, Scheduler}

  @columns ~w(PENDING QUALIFIED HIRED REJECTED NEEDS_HUMAN)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and
         Application.get_env(:showcase, :anthropic_client_impl) ==
           Showcase.Common.AnthropicClient.Mock do
      RecruitFlow.register_mock_responses()
    end

    {:ok,
     socket
     |> assign(:page_title, "RecruitFlow")
     |> assign(:columns, @columns)
     |> assign(:by_state, RecruitFlow.applications_by_state())
     |> assign(:phone_scenarios, MockPrompts.phone_scenarios())
     |> assign(:cv_scenarios, MockPrompts.cv_match_scenarios())
     |> assign(:last_tick_summary, nil)}
  end

  @impl true
  def handle_event("tick_scheduler", _params, socket) do
    summary = Scheduler.tick_all(%{now: DateTime.utc_now()})

    {:noreply,
     socket
     |> assign(:by_state, RecruitFlow.applications_by_state())
     |> assign(:last_tick_summary, summary)
     |> put_flash(:info, "Scheduler ticked: #{inspect(summary)}")}
  end

  def handle_event("run_ai_screen", %{"id" => id_string, "scenario" => scenario}, socket) do
    id =
      case id_string do
        i when is_integer(i) -> i
        s when is_binary(s) -> String.to_integer(s)
      end

    app = RecruitFlow.find_application(id)

    case PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:by_state, RecruitFlow.applications_by_state())
         |> put_flash(:info, "Phone screen complete.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Screen failed: #{inspect(reason)}")}
    end
  end

  def handle_event("cv_arrived", %{"scenario" => scenario_name}, socket) do
    scenario = Enum.find(socket.assigns.cv_scenarios, &(&1.name == scenario_name))

    payload = %{
      email: scenario.candidate_email,
      phone: scenario.candidate_phone,
      subject_line: scenario.subject_line,
      pdf_text: scenario.pdf_text
    }

    case CvMatcher.process_cv(payload, %{now: DateTime.utc_now()}) do
      {:ok, _cv, outcome} ->
        {:noreply,
         socket
         |> assign(:by_state, RecruitFlow.applications_by_state())
         |> put_flash(:info, "CV matched via #{outcome.step}.")}

      {:no_match, _} ->
        {:noreply, put_flash(socket, :info, "CV processed; no Application matched.")}
    end
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
          <div class="flex gap-3 items-center">
            <button
              type="button"
              class="rounded-lg bg-purple px-4 py-2 text-sm font-semibold text-white hover:opacity-90"
              phx-click="tick_scheduler"
            >
              Tick scheduler
            </button>
            <a href="/" class="text-sm text-ink/60 hover:text-purple transition-colors">
              &larr; Dashboard
            </a>
          </div>
        </div>

        <div class="max-w-7xl mx-auto px-6 pb-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Neurony · RecruitFlow
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            Recruitment funnel
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            5-state pipeline with AI phone screens + CV cascade matching.
          </p>
        </div>
        <%= if @last_tick_summary do %>
          <div class="max-w-7xl mx-auto px-6 pb-3 text-xs font-mono text-ink/60">
            Last tick: {inspect(@last_tick_summary)}
          </div>
        <% end %>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-6">
        <div class="grid grid-cols-5 gap-3">
          <section :for={state <- @columns} class="rounded-xl border border-line bg-white p-3 shadow-sm">
            <h2 class="text-xs uppercase tracking-wide text-ink/60 mb-2">{state}</h2>
            <ul class="space-y-2">
              <li :for={app <- Map.get(@by_state, state, [])} class="rounded border bg-surface-lav-2 p-2 text-xs">
                <a href={"/recruit-flow/applications/#{app.id}"} class="font-medium hover:underline">
                  {app.candidate.name}
                </a>
                <p class="text-ink/60 mt-0.5">{app.position && app.position.title}</p>
                <%= if state == "PENDING" do %>
                  <div class="mt-2 flex flex-col gap-1">
                    <button
                      :for={s <- @phone_scenarios}
                      type="button"
                      class="text-[10px] underline text-emerald-700 text-left"
                      phx-click="run_ai_screen"
                      phx-value-id={app.id}
                      phx-value-scenario={s.name}
                    >
                      Run as: {s.name}
                    </button>
                  </div>
                <% end %>
              </li>
            </ul>

            <%= if state == "QUALIFIED" and Map.get(@by_state, "QUALIFIED", []) != [] do %>
              <div class="mt-3 pt-3 border-t border-line">
                <p class="text-[10px] uppercase tracking-wide text-ink/50 mb-1">CV arrived:</p>
                <div class="flex flex-col gap-1">
                  <button
                    :for={cv <- @cv_scenarios}
                    type="button"
                    class="text-[10px] underline text-emerald-700 text-left"
                    phx-click="cv_arrived"
                    phx-value-scenario={cv.name}
                  >
                    {cv.name}
                  </button>
                </div>
              </div>
            <% end %>
          </section>
        </div>
      </main>
    </div>
    """
  end
end
