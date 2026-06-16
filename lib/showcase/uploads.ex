defmodule Showcase.Uploads do
  @moduledoc """
  One-stop helper for resolving an upload's URL path
  (e.g. `/uploads/restaurant_compliance/foo.jpg`) to its absolute on-disk
  path, using the runtime-configured `:uploads_root` from app config.

  Used by every demo's writer + reader to make sure both ends point at
  the same directory. In a release with a CWD ≠ project root (e.g. the
  Phoenix bin/server cd's to /app/bin), relative paths break — every
  upload writer/reader must go through this module.
  """

  @doc """
  Turn a stored URL path (`/uploads/<demo>/<file>`) into an absolute
  filesystem path that respects the `UPLOADS_ROOT` env var.
  """
  @spec resolve(String.t()) :: String.t()
  def resolve("/uploads/" <> rel), do: Path.join(root(), rel)
  def resolve("uploads/" <> rel), do: Path.join(root(), rel)
  def resolve(path) when is_binary(path), do: Path.join(root(), String.trim_leading(path, "/"))

  @doc "The configured uploads root directory."
  @spec root() :: String.t()
  def root, do: Application.get_env(:showcase, :uploads_root, "priv/static/uploads")
end
