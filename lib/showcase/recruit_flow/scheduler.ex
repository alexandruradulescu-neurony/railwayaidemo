defmodule Showcase.RecruitFlow.Scheduler do
  @moduledoc """
  RecruitFlow scheduler. One visible tick — `auto_close_stale_qualified` —
  demonstrates the AE-driven scheduler pattern without bloat.

  `tick_all/1` exists for UI symmetry; expand it as future ticks are added.
  """

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @stale_qualified_age_days 7

  def auto_close_stale_qualified(%{now: now}) do
    threshold = DateTime.add(now, -@stale_qualified_age_days, :day)

    ids =
      Repo.all(
        from a in Application,
          where: a.state == "QUALIFIED" and a.state_changed_at <= ^threshold,
          select: a.id
      )

    Enum.reduce(ids, 0, fn id, acc ->
      case Transitions.apply(id, "REJECTED", actor: "system", reason: "stale_no_cv") do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  def tick_all(%{now: _now} = ctx) do
    %{auto_close_stale_qualified: auto_close_stale_qualified(ctx)}
  end
end
