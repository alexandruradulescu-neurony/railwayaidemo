defmodule ShowcaseWeb.InvoiceApproval.QueueLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and
         Application.get_env(:showcase, :anthropic_client_impl) ==
           Showcase.Common.AnthropicClient.Mock do
      InvoiceApproval.register_mock_responses()
    end

    {:ok,
     socket
     |> assign(:page_title, "Invoice Approval")
     |> assign(:bundles, InvoiceApproval.list_bundles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-3 text-ink shrink-0">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a href="/" class="text-sm text-ink/60 hover:text-purple transition-colors">
            &larr; Dashboard
          </a>
        </div>
      </header>

      <div class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-6">
          <p class="font-body font-bold text-xs uppercase tracking-wider text-purple">
            Neurony · Invoice Approval
          </p>
          <h1 class="mt-2 font-heading font-bold text-3xl text-ink tracking-tight">
            Three-way invoice matching
          </h1>
          <p class="mt-2 font-body text-sm text-ink/60">
            Contract, delivery note, and invoice reconciled by AI. Configurable tolerances decide who needs a human.
          </p>
        </div>
      </div>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <h2 class="text-sm uppercase tracking-wide text-ink/60 mb-3">Bundles</h2>
        <ul class="space-y-2">
          <li :for={bundle <- @bundles} class="rounded-xl border border-line bg-white p-3 shadow-sm flex items-center justify-between">
            <div>
              <p class="font-medium text-sm">{bundle.client.name} · <span class="font-mono">{bundle.scenario}</span></p>
              <p class="text-xs text-ink/60 mt-1">{bundle.contract.name} · kind: {bundle.kind}</p>
            </div>
            <a
              href={"/invoice-approval/bundles/#{bundle.id}"}
              class="text-sm font-medium text-emerald-700"
            >
              Open →
            </a>
          </li>
        </ul>
      </main>
    </div>
    """
  end
end
