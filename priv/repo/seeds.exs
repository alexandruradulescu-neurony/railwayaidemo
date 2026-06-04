# Script for populating the database. Run with:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent — re-running produces identical baseline state.
#
# Enumerates `Showcase.Dashboard.live_seeders/0` so new live demos are picked
# up automatically when their tile flips from :coming_soon to :live.

require Logger

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

Logger.info("All live demos seeded. Visit http://localhost:4321/")
