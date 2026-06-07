defmodule Showcase.Planogram.Impl.ResultRenderer do
  @moduledoc """
  Pure mapper from raw vision JSON to view-model.

  Tolerates missing or type-malformed fields gracefully — `ResilientJSONParser`
  may return `:partial` results with arbitrary key drops or fragments. Every
  field has a default and a type-guarded extractor so the LiveView template
  never crashes, regardless of what the upstream JSON shape looks like.

  Sets `:partial?` to true when key required fields are absent, so the UI
  can show a "response was malformed, here's what we recovered" banner.

  ## View-model shape

      %{
        gauge_pct: 85,
        executive_summary: "...",
        issues: [%{type:, severity:, severity_color:, description:, row:, horizontal_position:, business_impact:}],
        extracted_prices: [%{text: "RON 15.99", row: 1, horizontal_position: "left"}],
        suggestions: [...],
        photo_quality: %{score:, notes:},

        # Derived counts for the stats sidebar
        mismatches_count: 12,
        prices_count: 45,
        out_of_stock_count: 2,

        # Legacy / structured detail
        rows: [...],
        unauthorized_items: [...],
        extracted_products: [...],

        partial?: false
      }
  """

  @required ~w(executive_summary issues photo_quality)

  # Issue types that count toward the "Mismatches Found" tile in the UI.
  @mismatch_types ~w(missing_product wrong_placement wrong_qty unauthorized_item mismatch)

  @spec render(map() | nil) :: map()
  def render(nil), do: render(%{})

  def render(raw) when is_map(raw) do
    issues = raw["issues"] |> as_list() |> Enum.map(&render_issue/1)
    prices = raw["extracted_prices"] |> as_list() |> Enum.map(&render_price/1)

    %{
      gauge_pct: clamp_gauge(raw["compliance_score"]),
      executive_summary: as_string(raw["executive_summary"], "(no summary returned)"),

      issues: issues,
      extracted_prices: prices,
      suggestions: as_list(raw["suggestions"]),
      photo_quality: render_photo_quality(raw["photo_quality"]),

      # Derived stats for the sidebar
      mismatches_count: Enum.count(issues, &(&1.type in @mismatch_types)),
      out_of_stock_count: Enum.count(issues, &(&1.type == "out_of_stock")),
      prices_count: length(prices),

      # Structured detail (kept for the per-row table + JSON inspector)
      rows: raw["rows"] |> as_list() |> Enum.map(&render_row/1),
      unauthorized_items: as_list(raw["unauthorized_items"]),
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
      business_impact: as_string(issue["business_impact"], ""),
      row: issue["row"],
      horizontal_position: as_string(issue["horizontal_position"], "center"),
      bbox: normalize_bbox(issue["bbox"]),
      badge: issue_badge(issue["type"])
    }
  end

  defp render_issue(_), do: render_issue(%{})

  defp render_price(p) when is_map(p) do
    %{
      text: as_string(p["text"], ""),
      row: p["row"],
      horizontal_position: as_string(p["horizontal_position"], "center"),
      bbox: normalize_bbox(p["bbox"])
    }
  end

  defp render_price(_), do: %{text: "", row: nil, horizontal_position: "center", bbox: nil}

  # Normalize a bbox map. Accepts string or atom keys, returns
  # %{x: float, y: float, w: float, h: float} clamped to [0, 1], or nil
  # if the input is missing/malformed/clearly bogus.
  #
  # Rejects boxes that:
  #   * have nil/non-numeric fields
  #   * sit entirely below the visible shelf area (y >= 0.95)
  #   * are degenerate (w or h < 0.005, i.e. < 0.5% of the photo)
  #   * extend wildly outside the frame (y + h > 1.1 or x + w > 1.1)
  defp normalize_bbox(b) when is_map(b) do
    x = fetch_float(b, "x")
    y = fetch_float(b, "y")
    w = fetch_float(b, "w")
    h = fetch_float(b, "h")

    cond do
      not Enum.all?([x, y, w, h], &is_number/1) ->
        nil

      y >= 0.95 ->
        nil

      w < 0.005 or h < 0.005 ->
        nil

      x + w > 1.1 or y + h > 1.1 ->
        nil

      true ->
        %{
          x: clamp01(x),
          y: clamp01(y),
          w: clamp01(w),
          h: clamp01(h)
        }
    end
  end

  defp normalize_bbox(_), do: nil

  defp fetch_float(m, k) do
    case Map.get(m, k) || Map.get(m, String.to_atom(k)) do
      n when is_number(n) -> n / 1
      _ -> nil
    end
  end

  defp clamp01(n) when is_number(n), do: max(0.0, min(1.0, n / 1))
  defp clamp01(_), do: 0.0

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

  @doc """
  Short human-readable badge for an issue type.

      iex> Showcase.Planogram.Impl.ResultRenderer.issue_badge("out_of_stock")
      "OUT OF STOCK"
  """
  @spec issue_badge(String.t() | nil) :: String.t()
  def issue_badge("missing_product"), do: "MISSING"
  def issue_badge("wrong_placement"), do: "WRONG PLACEMENT"
  def issue_badge("wrong_qty"), do: "WRONG QTY"
  def issue_badge("out_of_stock"), do: "OUT OF STOCK"
  def issue_badge("unauthorized_item"), do: "UNAUTHORIZED"
  def issue_badge("photo_quality"), do: "PHOTO QUALITY"
  def issue_badge("mismatch"), do: "MISMATCH"
  def issue_badge(_), do: "ISSUE"
end
