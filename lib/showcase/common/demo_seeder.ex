defmodule Showcase.Common.DemoSeeder do
  @moduledoc """
  Each demo provides a module implementing this behaviour. The dashboard
  reset orchestrator calls `c:tables/0` and `c:seed/0`.

  Seeders MUST be idempotent: running `seed/0` twice produces identical state.

  An optional `c:oban_queue/0` callback may be implemented by demos that
  enqueue background jobs; when present, `Showcase.Common.Reset` cancels
  pending jobs on that queue during reset.
  """

  @doc """
  The ordered list of table names this demo owns. Used by `Reset.truncate/1`.

  Example: `["of_orders", "of_order_lines", "of_product_aliases", "of_products", "of_clients"]`

  Order matters — Postgres `TRUNCATE` with `CASCADE` handles FKs, but for
  predictability list children before parents.
  """
  @callback tables() :: list(String.t())

  @doc """
  Idempotent re-seed of this demo's data. Called inside a transaction by
  the reset orchestrator.
  """
  @callback seed() :: :ok | {:error, term()}

  @doc """
  Human-readable demo name for dashboard tile and reset UI.
  """
  @callback name() :: String.t()

  @doc """
  Optional. One-line description of the demo for the dashboard tile.
  Used as the value-framing copy on the launcher.

  If not implemented, the tile falls back to the demo name as its description.
  """
  @callback description() :: String.t()

  @doc """
  Optional. The Oban queue name (atom) this demo enqueues jobs on. When
  defined, `Showcase.Common.Reset` will cancel pending jobs for this queue
  during a reset. If not implemented, reset skips job cancellation.
  """
  @callback oban_queue() :: atom() | nil

  @optional_callbacks description: 0, oban_queue: 0
end
