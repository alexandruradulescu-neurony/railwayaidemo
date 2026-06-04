defmodule Showcase.Repo do
  use AshPostgres.Repo,
    otp_app: :showcase,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    ["pg_trgm", "ash-functions"]
  end

  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end
