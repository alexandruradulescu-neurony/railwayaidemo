defmodule ShowcaseWeb.Plugs.Uploads do
  @moduledoc """
  Serves user uploads from a configurable directory.

  Standalone from Phoenix's `Plug.Static` because in a release the static
  app_dir (`/app/lib/showcase-VSN/priv/static`) is read-only and doesn't
  match where the upload writers persist files (`priv/static/uploads/...`
  relative to CWD = `/app/priv/static/uploads`). On Railway the volume
  mount lives at `/app/priv/static/uploads`, so reads have to bypass
  `Plug.Static` and go to an absolute path resolved at runtime.

  Configure via `:uploads_root` in app config; defaults to
  `"priv/static/uploads"` (relative — works in dev). In prod set the
  `UPLOADS_ROOT` env var (config/runtime.exs picks it up).
  """

  import Plug.Conn

  def init(_opts), do: []

  def call(%Plug.Conn{path_info: ["uploads" | rest]} = conn, _opts) when rest != [] do
    root = Application.get_env(:showcase, :uploads_root, "priv/static/uploads")

    # Reject `..` segments — defense against path traversal.
    if Enum.any?(rest, &(&1 in [".", ".."])) do
      conn |> send_resp(404, "") |> halt()
    else
      file = Path.join([root | rest])

      if File.regular?(file) do
        conn
        |> put_resp_content_type(MIME.from_path(file))
        |> send_file(200, file)
        |> halt()
      else
        conn |> send_resp(404, "") |> halt()
      end
    end
  end

  def call(conn, _opts), do: conn
end
