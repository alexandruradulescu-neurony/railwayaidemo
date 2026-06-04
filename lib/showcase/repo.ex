defmodule Showcase.Repo do
  # AshPostgres.Repo.__using__/1 invokes `use Ecto.Repo` internally
  # (see deps/ash_postgres/lib/repo.ex). Do NOT add a separate `use Ecto.Repo`
  # call — it will produce `def start_link/1 defines defaults multiple times`.
  use AshPostgres.Repo,
    otp_app: :showcase,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    ["pg_trgm", "ash-functions"]
  end

  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
