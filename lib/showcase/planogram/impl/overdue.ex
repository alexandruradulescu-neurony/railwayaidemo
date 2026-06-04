defmodule Showcase.Planogram.Impl.Overdue do
  @moduledoc """
  Pure functions for the date-driven overdue logic.

  Overdue is a query-time computed property — no cron mutates a status to
  "overdue". This module takes a task + a clock (passed as `Date`) and
  returns a boolean / bucket. Boundary code supplies the date so tests can
  pin the clock.
  """

  alias Showcase.Planogram.VerificationTask

  @spec overdue?(VerificationTask.t(), Date.t()) :: boolean()
  def overdue?(%VerificationTask{status: status}, _today)
      when status in ["complete", "failed"],
      do: false

  def overdue?(%VerificationTask{due_date: due_date}, today) do
    Date.compare(due_date, today) == :lt
  end

  @doc """
  Partition a list of tasks into display buckets given today's date.

  Returns a map with keys `:overdue`, `:today`, `:tomorrow`, `:later`, `:done`.
  """
  @spec bucket(list(VerificationTask.t()), Date.t()) :: %{
          overdue: list(VerificationTask.t()),
          today: list(VerificationTask.t()),
          tomorrow: list(VerificationTask.t()),
          later: list(VerificationTask.t()),
          done: list(VerificationTask.t())
        }
  def bucket(tasks, today) do
    Enum.reduce(tasks, %{overdue: [], today: [], tomorrow: [], later: [], done: []}, fn task,
                                                                                        acc ->
      key = bucket_key(task, today)
      Map.update!(acc, key, &[task | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp bucket_key(%VerificationTask{status: s}, _today) when s in ["complete", "failed"], do: :done

  defp bucket_key(%VerificationTask{due_date: due_date}, today) do
    case Date.compare(due_date, today) do
      :lt ->
        :overdue

      :eq ->
        :today

      :gt ->
        if Date.diff(due_date, today) == 1, do: :tomorrow, else: :later
    end
  end
end
