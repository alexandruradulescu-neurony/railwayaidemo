defmodule ShowcaseWeb.InvoiceApproval.Components.MatchingMatrix do
  @moduledoc """
  Renders the 3-column Contract / Delivery / Invoice matching matrix.

  Each row shows the line_key, per-doc values, and any classified
  discrepancies with severity-colored badges.
  """

  use Phoenix.Component

  attr :rows, :list, required: true,
    doc: "List of maps shaped like classified_matrix from Pipeline output"

  def matching_matrix(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm border-collapse">
        <thead class="bg-zinc-100 text-zinc-600 uppercase text-xs tracking-wide">
          <tr>
            <th class="py-2 px-3 text-left">Line</th>
            <th class="py-2 px-3 text-left">Contract</th>
            <th class="py-2 px-3 text-left">Delivery Note</th>
            <th class="py-2 px-3 text-left">Invoice</th>
            <th class="py-2 px-3 text-left">Discrepancies</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class={["border-t", row_bg(row)]}>
            <td class="py-3 px-3 font-mono text-xs">{row["line_key"]}</td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["contract"]} /></td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["delivery"]} /></td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["invoice"]} /></td>
            <td class="py-3 px-3 align-top">
              <ul :if={row["discrepancies"] not in [nil, []]} class="space-y-1">
                <li :for={cd <- row["discrepancies"]}>
                  <span class={severity_badge(cd["severity"])}>{cd["severity"]}</span>
                  <span class="ml-2 text-xs">{cd["discrepancy"]["field"]} · {cd["note"]}</span>
                </li>
              </ul>
              <span :if={row["discrepancies"] in [nil, []]} class="text-xs text-emerald-600">✓ match</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp cell(assigns) do
    assigns = assign_new(assigns, :map, fn -> %{} end)

    ~H"""
    <%= if @map in [nil, %{}] do %>
      <span class="text-zinc-400">—</span>
    <% else %>
      <ul class="font-mono text-xs space-y-0.5">
        <li :for={{k, v} <- @map}>{k}: {format_value(v)}</li>
      </ul>
    <% end %>
    """
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_value(v), do: to_string(v)

  defp row_bg(%{"discrepancies" => discs}) when is_list(discs) and discs != [] do
    severities = Enum.map(discs, & &1["severity"])

    cond do
      "red" in severities -> "bg-red-50"
      "amber" in severities -> "bg-amber-50"
      true -> "bg-emerald-50"
    end
  end

  defp row_bg(_), do: "bg-emerald-50"

  defp severity_badge("green"),
    do: "inline-block rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-emerald-300"

  defp severity_badge("amber"),
    do: "inline-block rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-900 ring-1 ring-amber-300"

  defp severity_badge("red"),
    do: "inline-block rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-900 ring-1 ring-red-300"

  defp severity_badge(_), do: "inline-block rounded-full bg-zinc-100 px-2 py-0.5 text-xs"
end
