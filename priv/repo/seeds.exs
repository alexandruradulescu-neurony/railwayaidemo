# Script for populating the database. Run with:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent — re-running produces identical baseline state.

require Logger

Logger.info("Seeding OrderFlow demo data...")

case Showcase.OrderFlow.Seed.seed() do
  :ok ->
    Logger.info("OrderFlow seeded. Visit http://localhost:4000/order-flow")

  {:error, reason} ->
    Logger.error("OrderFlow seed failed: #{inspect(reason)}")
    System.halt(1)
end
