defmodule ShowcaseWeb.Plugs.AdminBasicAuth do
  @moduledoc """
  HTTP basic auth gate for admin routes. Credentials read from app config
  (which in turn reads `ADMIN_USER` / `ADMIN_PASS` env vars via runtime.exs).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected_user = Application.fetch_env!(:showcase, :admin_user)
    expected_pass = Application.fetch_env!(:showcase, :admin_pass)

    case Plug.BasicAuth.parse_basic_auth(conn) do
      {^expected_user, ^expected_pass} ->
        conn

      _ ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="Showcase Admin"))
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
