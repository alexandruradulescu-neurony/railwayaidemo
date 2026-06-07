defmodule ShowcaseWeb.Plugs.AdminBasicAuth do
  @moduledoc """
  HTTP basic auth gate for admin routes. Credentials read from app config
  (which in turn reads `ADMIN_USER` / `ADMIN_PASS` env vars via runtime.exs).

  Uses `Plug.BasicAuth.basic_auth/2` so the credential comparison is
  constant-time. Pattern-matching on raw binaries (the previous impl)
  used Erlang's default byte-by-byte comparison, which is technically a
  timing-side-channel — fine for a localhost demo but a bad reference
  pattern (REVIEW.md HI-08).
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.BasicAuth.basic_auth(conn,
      username: Application.fetch_env!(:showcase, :admin_user),
      password: Application.fetch_env!(:showcase, :admin_pass),
      realm: "Showcase Admin"
    )
  end
end
