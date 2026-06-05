defmodule Showcase.Planogram do
  @moduledoc """
  Public boundary for the Planogram Manager demo.

  Read paths (list_tasks, get_task, list_planograms) are plain Ecto.
  Write paths that enqueue Oban jobs (enqueue_analysis/1) live here.
  """

  import Ecto.Query

  alias Showcase.Planogram.{Planogram, VerificationTask, Worker, Impl.Overdue}
  alias Showcase.Repo

  @spec list_tasks() :: list(VerificationTask.t())
  def list_tasks do
    from(t in VerificationTask, preload: [:planogram], order_by: [asc: t.due_date])
    |> Repo.all()
  end

  @spec get_task!(integer()) :: VerificationTask.t()
  def get_task!(id) do
    VerificationTask
    |> Repo.get!(id)
    |> Repo.preload(:planogram)
  end

  @spec list_planograms() :: list(Planogram.t())
  def list_planograms do
    Repo.all(from p in Planogram, order_by: [asc: p.name])
  end

  @spec bucket_tasks(Date.t()) :: map()
  def bucket_tasks(today \\ Date.utc_today()) do
    list_tasks() |> Overdue.bucket(today)
  end

  @doc """
  Enqueue an analysis job for the given task. Optional `:max_tokens` for
  the force-truncation demo.
  """
  @spec enqueue_analysis(integer(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_analysis(task_id, opts \\ []) do
    args = %{"task_id" => task_id}

    args =
      case Keyword.get(opts, :max_tokens) do
        nil -> args
        n when is_integer(n) -> Map.put(args, "max_tokens", n)
      end

    args |> Worker.new() |> Oban.insert()
  end

  @doc """
  Create a manager-authored task. Used by the Manager view.
  """
  @spec create_task(map()) :: {:ok, VerificationTask.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    attrs =
      attrs
      |> Map.put_new("mobile_token", Showcase.Planogram.MobileHandoff.generate_token())
      |> Map.put_new("status", "pending")

    %VerificationTask{}
    |> VerificationTask.changeset(attrs)
    |> Repo.insert()
  end
end
