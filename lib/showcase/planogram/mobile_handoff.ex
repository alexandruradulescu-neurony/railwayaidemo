defmodule Showcase.Planogram.MobileHandoff do
  @moduledoc """
  Coordinates the desktop ↔ phone handoff flow.

  Lifecycle:
    1. Manager creates a task → `generate_token/0` assigns it a URL-safe
       random token (also written to DB at insert time).
    2. Merchandiser view renders a QR encoding `/planogram/mobile/<token>`.
    3. Phone scans, hits `MobileCaptureLive`, uploads a photo.
    4. `finalize_upload/2` writes the bytes to `priv/static/uploads/planogram/`
       and stores the relative path in `task.photo_path`.
    5. Desktop's PubSub subscription notices the photo is in place and
       enables the "Run analysis" button.
  """

  alias Showcase.Planogram.VerificationTask
  alias Showcase.Repo

  @upload_dir "priv/static/uploads/planogram"

  @spec generate_token() :: String.t()
  def generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @spec find_task_by_token(String.t()) ::
          {:ok, VerificationTask.t()} | {:error, :not_found | :already_processed}
  def find_task_by_token(token) when is_binary(token) do
    case Repo.get_by(VerificationTask, mobile_token: token) do
      nil ->
        {:error, :not_found}

      %VerificationTask{status: s} when s in ["complete", "failed"] ->
        {:error, :already_processed}

      task ->
        {:ok, task}
    end
  end

  @spec finalize_upload(VerificationTask.t(), binary()) ::
          {:ok, VerificationTask.t()} | {:error, term()}
  def finalize_upload(%VerificationTask{} = task, bytes) when is_binary(bytes) do
    File.mkdir_p!(@upload_dir)
    extension = if String.starts_with?(bytes, <<137, 80, 78, 71>>), do: ".png", else: ".jpg"
    filename = "#{task.id}-#{System.unique_integer([:positive])}#{extension}"
    full_path = Path.join(@upload_dir, filename)
    File.write!(full_path, bytes)

    relative = "/uploads/planogram/#{filename}"

    task
    |> VerificationTask.changeset(%{photo_path: relative})
    |> Repo.update()
  end
end
