defmodule Showcase.Planogram.Impl.ResultRenderer do
  @moduledoc """
  Pure mapper from raw vision JSON to view-model.

  Tolerates missing or type-malformed fields gracefully — `ResilientJSONParser`
  may return `:partial` results with arbitrary key drops or fragments. Every
  field has a default and a type-guarded extractor so the LiveView template
  never crashes, regardless of what the upstream JSON shape looks like.

  Sets `:partial?` to true when key required fields are absent, so the UI
  can show a "response was malformed, here's what we recovered" banner.
  """

  @required ~w(executive_summary rows issues photo_quality)

  @spec render(map() | nil) :: map()
  def render(nil), do: render(%{})

  def render(raw) when is_map(raw) do
    %{
      gauge_pct: clamp_gauge(raw["compliance_score"]),
      executive_summary: as_string(raw["executive_summary"], "(no summary returned)"),
      rows: raw["rows"] |> as_list() |> Enum.map(&render_row/1),
      issues: raw["issues"] |> as_list() |> Enum.map(&render_issue/1),
      unauthorized_items: as_list(raw["unauthorized_items"]),
      suggestions: as_list(raw["suggestions"]),
      photo_quality: render_photo_quality(raw["photo_quality"]),
      extracted_products: as_list(raw["extracted_products"]),
      partial?: partial?(raw)
    }
  end

  def render(_non_map), do: render(%{})

  defp clamp_gauge(n) when is_integer(n), do: max(0, min(100, n))
  defp clamp_gauge(n) when is_float(n), do: clamp_gauge(round(n))
  defp clamp_gauge(_), do: 0

  defp render_row(row) when is_map(row) do
    %{
      name: as_string(row["name"], "(unnamed row)"),
      position: row["position"],
      status: as_string(row["status"], "unknown"),
      status_color: row_status_color(row["status"]),
      found_products: as_list(row["found_products"]),
      issues: as_list(row["issues"])
    }
  end

  defp render_row(_), do: render_row(%{})

  defp render_issue(issue) when is_map(issue) do
    %{
      type: as_string(issue["type"], "unknown"),
      severity: as_string(issue["severity"], "low"),
      severity_color: severity_color(issue["severity"]),
      description: as_string(issue["description"], ""),
      business_impact: as_string(issue["business_impact"], "")
    }
  end

  defp render_issue(_), do: render_issue(%{})

  defp render_photo_quality(pq) when is_map(pq),
    do: %{score: pq["score"], notes: pq["notes"]}

  defp render_photo_quality(_), do: %{score: nil, notes: nil}

  defp as_list(x) when is_list(x), do: x
  defp as_list(_), do: []

  defp as_string(x, _default) when is_binary(x), do: x
  defp as_string(_, default), do: default

  defp partial?(raw) do
    Enum.any?(@required, &(not Map.has_key?(raw, &1)))
  end

  @spec row_status_color(String.t() | nil) :: String.t()
  def row_status_color("compliant"), do: "emerald"
  def row_status_color("partial"), do: "amber"
  def row_status_color("non_compliant"), do: "rose"
  def row_status_color(_), do: "zinc"

  @spec severity_color(String.t() | nil) :: String.t()
  def severity_color("high"), do: "rose"
  def severity_color("medium"), do: "amber"
  def severity_color("low"), do: "zinc"
  def severity_color(_), do: "zinc"
end
