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
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Invoice Approval</h1>
            <p class="text-sm text-zinc-500 mt-1">
              3-way matching across contract, delivery note, and invoice.
            </p>
          </div>
          <a href="/" class="text-sm text-zinc-500 underline">&larr; Dashboard</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Bundles</h2>
        <ul class="space-y-2">
          <li :for={bundle <- @bundles} class="rounded border bg-white p-3 flex items-center justify-between">
            <div>
              <p class="font-medium text-sm">{bundle.client.name} · <span class="font-mono">{bundle.scenario}</span></p>
              <p class="text-xs text-zinc-500 mt-1">{bundle.contract.name} · kind: {bundle.kind}</p>
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
