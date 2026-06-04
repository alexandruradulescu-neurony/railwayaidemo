defmodule ShowcaseWeb.Plugs.AdminBasicAuthTest do
  use ShowcaseWeb.ConnCase, async: true

  alias ShowcaseWeb.Plugs.AdminBasicAuth

  setup do
    Application.put_env(:showcase, :admin_user, "admin")
    Application.put_env(:showcase, :admin_pass, "secret")
    :ok
  end

  test "denies request with no credentials", %{conn: conn} do
    conn = AdminBasicAuth.call(conn, [])
    assert conn.status == 401
    assert {"www-authenticate", _} = List.keyfind(conn.resp_headers, "www-authenticate", 0)
    assert conn.halted
  end

  test "denies request with bad credentials", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Basic " <> Base.encode64("wrong:wrong"))
      |> AdminBasicAuth.call([])

    assert conn.status == 401
    assert conn.halted
  end

  test "allows request with correct credentials", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Basic " <> Base.encode64("admin:secret"))
      |> AdminBasicAuth.call([])

    refute conn.halted
  end
end
