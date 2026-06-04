defmodule Showcase.Planogram.Impl.ResultRenderer do
  @moduledoc """
  Pure mapper from raw vision JSON to view-model.

  Tolerates missing fields gracefully — `ResilientJSONParser` may return
  `:partial` results with arbitrary key drops. Every field has a default
  so the LiveView template never crashes on `nil`.

  Sets `:partial?` to true when key required fields are absent, so the UI
  can show a "response was malformed, here's what we recovered" banner.
  """

  @required ~w(executive_summary rows issues photo_quality)

  @spec render(map() | nil) :: map()
  def render(nil), do: render(%{})

  def render(raw) when is_map(raw) do
    %{
      gauge_pct: clamp_gauge(raw["compliance_score"]),
      executive_summary: raw["executive_summary"] || "(no summary returned)",
      rows: Enum.map(raw["rows"] || [], &render_row/1),
      issues: Enum.map(raw["issues"] || [], &render_issue/1),
      unauthorized_items: raw["unauthorized_items"] || [],
      suggestions: raw["suggestions"] || [],
      photo_quality: render_photo_quality(raw["photo_quality"]),
      extracted_products: raw["extracted_products"] || [],
      partial?: partial?(raw)
    }
  end

  defp clamp_gauge(n) when is_integer(n), do: max(0, min(100, n))
  defp clamp_gauge(n) when is_float(n), do: clamp_gauge(round(n))
  defp clamp_gauge(_), do: 0

  defp render_row(row) do
    %{
      name: row["name"] || "(unnamed row)",
      position: row["position"],
      status: row["status"] || "unknown",
      status_color: row_status_color(row["status"]),
      found_products: row["found_products"] || [],
      issues: row["issues"] || []
    }
  end

  defp render_issue(issue) do
    %{
      type: issue["type"] || "unknown",
      severity: issue["severity"] || "low",
      severity_color: severity_color(issue["severity"]),
      description: issue["description"] || "",
      business_impact: issue["business_impact"] || ""
    }
  end

  defp render_photo_quality(nil), do: %{score: nil, notes: nil}

  defp render_photo_quality(pq) when is_map(pq),
    do: %{score: pq["score"], notes: pq["notes"]}

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
