defmodule Showcase.Planogram.Worker do
  @moduledoc """
  Oban worker for the planogram vision pipeline.

  Args: `%{"task_id" => integer, "max_tokens" => integer (optional)}`.

  Reads the shelf photo from disk (uploaded by Merchandiser or via the
  mobile QR handoff) and the reference planogram image (uploaded by
  Manager) and hands off to `VisionPipeline.analyze/2`. NO bundled
  fallback images — if no shelf photo is uploaded, the pipeline fails
  cleanly with `:no_photo_attached` so the AE knows to upload one.
  """

  use Oban.Worker, queue: :planogram, max_attempts: 3

  alias Showcase.Planogram.{VerificationTask, VisionPipeline}
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id} = args}) do
    case Repo.get(VerificationTask, task_id) |> Repo.preload(:planogram) do
      nil ->
        {:error, :task_not_found}

      task ->
        photo_bytes = read_photo(task)
        reference_bytes = read_reference(task)
        max_tokens = Map.get(args, "max_tokens", 4096)

        opts =
          [photo_bytes: photo_bytes, max_tokens: max_tokens]
          |> maybe_put(:reference_bytes, reference_bytes)

        case VisionPipeline.analyze(task, opts) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
          # NB: pipeline already marked the task failed and broadcast — Oban
          # should NOT retry on parse/no-photo errors. We swallow the {:error}
          # to keep Oban from re-running.
        end
    end
  end

  # ── Shelf photo (the one being audited) ──────────────────────────────
  # Returns the bytes if a real user-uploaded photo is on disk, else nil.
  # NO bundled fallbacks — the pipeline must fail cleanly when there's no
  # photo, rather than silently feed Claude a placeholder PNG.

  defp read_photo(%VerificationTask{photo_path: nil}), do: nil

  defp read_photo(%VerificationTask{photo_path: path}) when is_binary(path) do
    case File.read(Showcase.Uploads.resolve(path)) do
      {:ok, bytes} -> bytes
      {:error, _} -> nil
    end
  end

  # ── Reference planogram image ────────────────────────────────────────

  defp read_reference(%VerificationTask{planogram: %{reference_image_path: path}})
       when is_binary(path) do
    # Reference images live in the release's static dir.
    full = Path.join(Application.app_dir(:showcase, "priv/static"), String.trim_leading(path, "/"))

    case safe_read_optional(full) do
      {:ok, bytes} when byte_size(bytes) > 100 -> bytes
      # Tiny placeholder PNGs (< 100 bytes) are not useful as references;
      # skip them so the pipeline falls back to single-image mode.
      _ -> nil
    end
  end

  defp read_reference(_), do: nil

  # ── helpers ──────────────────────────────────────────────────────────

  defp safe_read_optional(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _} -> :not_found
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
