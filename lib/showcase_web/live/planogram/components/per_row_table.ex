defmodule ShowcaseWeb.Planogram.Components.PerRowTable do
  @moduledoc """
  Per-shelf-row breakdown table. Expects rows as produced by
  `Showcase.Planogram.Impl.ResultRenderer.render/1` — each row is a map
  with `:name`, `:status`, `:status_color`, `:found_products`, and `:issues`.
  """
  use Phoenix.Component

  attr :rows, :list, required: true

  def per_row_table(assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead class="text-xs uppercase tracking-wide text-ink/60">
        <tr>
          <th class="text-left py-2">Row</th>
          <th class="text-left py-2">Status</th>
          <th class="text-left py-2">Found products</th>
          <th class="text-left py-2">Issues</th>
        </tr>
      </thead>
      <tbody class="divide-y">
        <tr :for={row <- @rows}>
          <td class="py-2 font-medium"><%= row.name %></td>
          <td class="py-2">
            <span class={["rounded px-2 py-0.5 text-xs",
                          "bg-#{row.status_color}-100 text-#{row.status_color}-700"]}>
              <%= row.status %>
            </span>
          </td>
          <td class="py-2">
            <%= for p <- row.found_products do %>
              <div><%= p["name"] %> <span class="text-ink/50">×<%= p["qty"] %></span></div>
            <% end %>
          </td>
          <td class="py-2 text-ink/80">
            <ul class="list-disc list-inside">
              <li :for={iss <- row.issues}><%= iss %></li>
            </ul>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end
end
