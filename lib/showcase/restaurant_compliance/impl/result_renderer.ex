defmodule Showcase.RestaurantCompliance.Impl.ResultRenderer do
  @moduledoc """
  Pure mapper from raw vision JSON to view-model.

  Tolerates missing or type-malformed fields gracefully — `ResilientJSONParser`
  may return `:partial` results with arbitrary key drops. Every field has a
  default and a type-guarded extractor so the LiveView template never crashes.

  ## View-model shape

      %{
        gauge_pct: 78,
        overall_summary: "...",
        rule_evaluations: [
          %{rule:, status:, severity:, severity_color:, status_color:,
            status_icon:, evidence:, photo_indices: [1, 2]}
        ],
        photo_violations: [
          %{photo_index: 1,
            issues: [%{description:, severity:, severity_color:}]}
        ],
        remediation_steps: [...],
        pass_count: 3,
        partial_count: 1,
        fail_count: 5,
        not_applicable_count: 0,
        total_rules: 9,
        partial?: false
      }
  """

  @required ~w(overall_summary rule_evaluations)

  @spec render(map() | nil) :: map()
  def render(nil), do: render(%{})

  def render(raw) when is_map(raw) do
    rule_evaluations =
      raw["rule_evaluations"]
      |> as_list()
      |> Enum.map(&render_rule_eval/1)

    photo_violations =
      raw["photo_violations"]
      |> as_list()
      |> Enum.map(&render_photo_violation/1)

    pass = Enum.count(rule_evaluations, &(&1.status == "pass"))
    fail = Enum.count(rule_evaluations, &(&1.status == "fail"))
    partial = Enum.count(rule_evaluations, &(&1.status == "partial"))
    na = Enum.count(rule_evaluations, &(&1.status == "not_applicable"))

    %{
      gauge_pct: clamp_gauge(raw["compliance_score"]),
      overall_summary: as_string(raw["overall_summary"], "(no summary returned)"),
      rule_evaluations: rule_evaluations,
      photo_violations: photo_violations,
      remediation_steps: raw["remediation_steps"] |> as_list() |> Enum.map(&as_string(&1, "")),
      pass_count: pass,
      fail_count: fail,
      partial_count: partial,
      not_applicable_count: na,
      total_rules: length(rule_evaluations),
      partial?: partial?(raw)
    }
  end

  def render(_), do: render(%{})

  defp clamp_gauge(n) when is_integer(n), do: max(0, min(100, n))
  defp clamp_gauge(n) when is_float(n), do: clamp_gauge(round(n))
  defp clamp_gauge(_), do: 0

  defp render_rule_eval(eval) when is_map(eval) do
    status = as_string(eval["status"], "fail")
    severity = as_string(eval["severity"], "low")

    %{
      rule: as_string(eval["rule"], "(unnamed rule)"),
      status: status,
      severity: severity,
      status_color: status_color(status),
      status_icon: status_icon(status),
      severity_color: severity_color(severity),
      evidence: as_string(eval["evidence"], ""),
      photo_indices: as_int_list(eval["photo_indices"])
    }
  end

  defp render_rule_eval(_), do: render_rule_eval(%{})

  defp render_photo_violation(pv) when is_map(pv) do
    %{
      photo_index: as_int(pv["photo_index"], 0),
      issues:
        pv["issues"]
        |> as_list()
        |> Enum.map(fn iss when is_map(iss) ->
          severity = as_string(iss["severity"], "low")

          %{
            description: as_string(iss["description"], ""),
            severity: severity,
            severity_color: severity_color(severity)
          }
        end)
    }
  end

  defp render_photo_violation(_), do: %{photo_index: 0, issues: []}

  @spec status_color(String.t() | nil) :: String.t()
  def status_color("pass"), do: "emerald"
  def status_color("partial"), do: "amber"
  def status_color("fail"), do: "rose"
  def status_color("not_applicable"), do: "zinc"
  def status_color(_), do: "zinc"

  @spec status_icon(String.t() | nil) :: String.t()
  def status_icon("pass"), do: "hero-check-circle"
  def status_icon("partial"), do: "hero-minus-circle"
  def status_icon("fail"), do: "hero-x-circle"
  def status_icon("not_applicable"), do: "hero-question-mark-circle"
  def status_icon(_), do: "hero-question-mark-circle"

  @spec severity_color(String.t() | nil) :: String.t()
  def severity_color("high"), do: "rose"
  def severity_color("medium"), do: "amber"
  def severity_color("low"), do: "zinc"
  def severity_color(_), do: "zinc"

  defp as_list(x) when is_list(x), do: x
  defp as_list(_), do: []

  defp as_string(x, _default) when is_binary(x), do: x
  defp as_string(_, default), do: default

  defp as_int(x, _default) when is_integer(x), do: x
  defp as_int(x, _default) when is_float(x), do: round(x)
  defp as_int(_, default), do: default

  defp as_int_list(xs) when is_list(xs) do
    xs
    |> Enum.map(&as_int(&1, nil))
    |> Enum.reject(&is_nil/1)
  end

  defp as_int_list(_), do: []

  defp partial?(raw) do
    Enum.any?(@required, &(not Map.has_key?(raw, &1)))
  end
end
