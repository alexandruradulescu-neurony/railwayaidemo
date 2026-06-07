defmodule Showcase.Planogram.Worker do
  @moduledoc """
  Oban worker for the planogram vision pipeline.

  Args: `%{"task_id" => integer, "max_tokens" => integer (optional)}`.

  Reads the photo bytes from disk (either from the uploaded path or a
  bundled scenario fallback under `priv/static/images/planogram/`) and
  hands off to `VisionPipeline.analyze/2`.
  """

  use Oban.Worker, queue: :planogram, max_attempts: 3

  alias Showcase.Planogram.{VerificationTask, VisionPipeline}
  alias Showcase.Repo

  @bundled_dir "priv/static/images/planogram"

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

  defp read_photo(%VerificationTask{photo_path: "/uploads/" <> _ = path}) do
    File.read!(Path.join("priv/static", path))
  end

  defp read_photo(%VerificationTask{photo_path: path}) when is_binary(path) do
    File.read!(Path.join("priv/static", String.trim_leading(path, "/")))
  rescue
    _ -> bundled_shelf_fallback(nil)
  end

  defp read_photo(%VerificationTask{photo_path: nil, scenario: scenario}) do
    bundled_shelf_fallback(scenario)
  end

  defp bundled_shelf_fallback(scenario) do
    filename =
      case scenario do
        "compliant" -> "captured_compliant.png"
        "minor_issues" -> "captured_minor_issues.png"
        "major_issues" -> "captured_major_issues.png"
        _ -> "captured_compliant.png"
      end

    safe_read(Path.join(@bundled_dir, filename))
  end

  # ── Reference planogram image ────────────────────────────────────────

  defp read_reference(%VerificationTask{planogram: %{reference_image_path: path}})
       when is_binary(path) do
    case safe_read_optional(Path.join("priv/static", String.trim_leading(path, "/"))) do
      {:ok, bytes} when byte_size(bytes) > 100 -> bytes
      # Tiny placeholder PNGs (< 100 bytes) are not useful as references;
      # skip them so the pipeline falls back to single-image mode.
      _ -> nil
    end
  end

  defp read_reference(_), do: nil

  # ── helpers ──────────────────────────────────────────────────────────

  defp safe_read(path) do
    case File.read(path) do
      {:ok, bytes} -> bytes
      # Fallback to a minimal PNG header so dev/CI runs before real bundled
      # images are committed.
      {:error, _} -> <<137, 80, 78, 71, 13, 10, 26, 10>>
    end
  end

  defp safe_read_optional(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _} -> :not_found
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
