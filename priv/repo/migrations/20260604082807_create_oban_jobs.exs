defmodule Showcase.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  # Oban.Migration.up/0 auto-detects the latest schema version supported by
  # the installed Oban package. If your installed Oban is older and rejects
  # the call, pin explicitly with `Oban.Migration.up(version: N)` per the
  # `Oban.Migration` docs for your version.
  def up, do: Oban.Migration.up()

  def down, do: Oban.Migration.down(version: 1)
end
