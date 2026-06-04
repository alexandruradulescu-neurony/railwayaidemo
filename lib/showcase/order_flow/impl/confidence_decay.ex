defmodule Showcase.OrderFlow.Impl.ConfidenceDecay do
  @moduledoc """
  Pure time-adjustment of alias confidence.

    * `< 6 months` since `last_used_at` → `raw_confidence` (unchanged).
    * `6 to 12 months` → linear decay from `raw_confidence` to `@floor` (`0.1`).
    * `>= 12 months` → `:expired` (caller filters out).

  Returns a `float() | :expired`. The boundary supplies `now` so this stays pure.
  """

  @floor 0.1
  @fresh_days 180
  @stale_days 365

  @spec decay(float(), DateTime.t(), DateTime.t()) :: float() | :expired
  def decay(raw_confidence, %DateTime{} = last_used_at, %DateTime{} = now)
      when is_float(raw_confidence) do
    days = DateTime.diff(now, last_used_at, :second) / 86_400.0

    cond do
      days < @fresh_days ->
        raw_confidence

      days >= @stale_days ->
        :expired

      true ->
        # Decay window is [@fresh_days, @stale_days). Offset by 1 day so that
        # crossing the threshold yields a small but non-zero decay (day 180 is
        # already "in decay"); the floor is approached as days approach
        # @stale_days.
        progress = (days - @fresh_days + 1) / (@stale_days - @fresh_days)
        raw_confidence - progress * (raw_confidence - @floor)
    end
  end
end
