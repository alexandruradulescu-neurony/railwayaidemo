defmodule Showcase.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  Called from the `bin/migrate` and `bin/seed` scripts in `rel/overlays/`
  (Railway/prod) — never from dev/test, where you use `mix ecto.migrate`
  and `mix run priv/repo/seeds.exs` instead.
  """
  @app :showcase

  require Logger

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Run every live demo's seed function. Idempotent — re-running yields
  the same baseline state. Safe to call on every deploy: each seeder
  uses `on_conflict: :nothing` or `Repo.get_by` guards.

  Halts the BEAM with a non-zero exit code on any seeder failure so the
  deploy fails loudly rather than silently advancing to a broken state.
  """
  def seed do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Showcase.Repo, fn _repo ->
        Showcase.Dashboard.live_seeders()
        |> Enum.each(fn seeder ->
          Logger.info("Seeding #{seeder.name()}...")

          case seeder.seed() do
            :ok ->
              Logger.info("#{seeder.name()} seeded.")

            {:error, reason} ->
              Logger.error("#{seeder.name()} seed failed: #{inspect(reason)}")
              System.halt(1)
          end
        end)
      end)

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
