defmodule Showcase.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  # Pinned to schema v14 (latest supported by Oban 2.23.0 at install time).
  # Pinning prevents `mix deps.update` from silently upgrading the schema on
  # the next deploy. To upgrade intentionally: bump this value and add a new
  # migration. See `Oban.Migration` docs for the upgrade path.
  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 1)
end
