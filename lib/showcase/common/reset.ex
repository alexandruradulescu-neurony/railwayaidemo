defmodule Showcase.Common.Reset do
  @moduledoc """
  Orchestrates per-demo and global resets.

  Steps:
    1. Cancel in-flight Oban jobs for each demo's queue.
    2. TRUNCATE the demo's tables (enumerated by the seeder's `tables/0`).
    3. Call the seeder's `seed/0` to re-populate baseline state.
    4. Broadcast `{:reset, demo_name}` on `<topic_prefix>:<slug>:reset` per demo.

  **Transactionality:** Steps 2 and 3 run inside a single `Ecto.Multi`
  transaction — truncate + reseed are atomic relative to each other. Step 1
  (Oban cancel) writes to the `oban_jobs` table via `Oban.cancel_all_jobs/1`
  and is NOT rolled back if a later step fails — cancellations are
  fire-and-forget. Step 4 (broadcast) only runs on transaction success.

  In practice this is fine: if reset aborts mid-flight, the dev runs reset
  again. The point of the Multi is to keep the database internally consistent
  even on partial failure, not to make Oban transactional with Postgres.
  """

  import Ecto.Query, only: [where: 3]

  alias Ecto.Multi
  alias Showcase.Repo

  @type opts :: [topic_prefix: String.t() | nil]

  @spec run(list(module()), opts()) :: :ok | {:error, term()}
  def run(seeders, opts \\ []) when is_list(seeders) do
    topic_prefix = Keyword.get(opts, :topic_prefix, "demo")

    multi =
      seeders
      |> Enum.reduce(Multi.new(), fn seeder, acc ->
        acc
        |> Multi.run({:cancel_jobs, seeder}, fn _repo, _ ->
          cancel_jobs_for(seeder)
          {:ok, :cancelled}
        end)
        |> Multi.run({:truncate, seeder}, fn _repo, _ ->
          truncate_tables(seeder.tables())
          {:ok, :truncated}
        end)
        |> Multi.run({:seed, seeder}, fn _repo, _ ->
          case seeder.seed() do
            :ok -> {:ok, :seeded}
            {:error, _} = err -> err
          end
        end)
      end)

    case Repo.transaction(multi) do
      {:ok, _} ->
        Enum.each(seeders, fn seeder ->
          Phoenix.PubSub.broadcast(
            Showcase.PubSub,
            "#{topic_prefix}:#{slug(seeder)}:reset",
            {:reset, seeder.name()}
          )
        end)

        :ok

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp truncate_tables(tables) when is_list(tables) do
    sql = "TRUNCATE TABLE #{Enum.join(tables, ", ")} RESTART IDENTITY CASCADE"
    Ecto.Adapters.SQL.query!(Repo, sql, [])
    :ok
  end

  defp cancel_jobs_for(seeder) do
    queue = queue_for(seeder)

    if queue do
      queue_str = to_string(queue)
      Oban.cancel_all_jobs(where(Oban.Job, [j], j.queue == ^queue_str))
    else
      :ok
    end
  end

  # Maps a seeder module to its Oban queue. Override per-demo if needed.
  defp queue_for(seeder) do
    if function_exported?(seeder, :oban_queue, 0), do: seeder.oban_queue(), else: nil
  end

  defp slug(seeder), do: seeder.name() |> String.downcase() |> String.replace(~r/\s+/, "-")
end
