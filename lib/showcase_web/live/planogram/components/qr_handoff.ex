defmodule ShowcaseWeb.Planogram.Components.QRHandoff do
  @moduledoc """
  Renders a QR code (as SVG) pointing at the mobile capture URL for a
  planogram verification task. The Merchandiser scans this with their
  phone to upload a shelf photo without leaving the desk.
  """
  use Phoenix.Component

  attr :url, :string, required: true
  attr :size, :integer, default: 240

  def qr_handoff(assigns) do
    svg =
      assigns.url
      |> EQRCode.encode()
      |> EQRCode.svg(viewbox: true, width: assigns.size)

    assigns = assign(assigns, :svg, svg)

    ~H"""
    <div class="inline-block rounded border bg-white p-3">
      <div class="mb-2 text-xs uppercase tracking-wide text-zinc-500">
        Open on phone
      </div>
      {Phoenix.HTML.raw(@svg)}
      <div class="mt-2 break-all text-xs text-zinc-400">{@url}</div>
    </div>
    """
  end
end
