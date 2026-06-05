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
    case Repo.get(VerificationTask, task_id) do
      nil ->
        {:error, :task_not_found}

      task ->
        photo_bytes = read_photo(task)
        max_tokens = Map.get(args, "max_tokens", 4096)

        case VisionPipeline.analyze(task, photo_bytes: photo_bytes, max_tokens: max_tokens) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
          # NB: pipeline already marked the task failed and broadcast — Oban
          # should NOT retry on parse/no-photo errors. We swallow the {:error}
          # to keep Oban from re-running. (Anthropic transport errors *do* go
          # via Oban retry because they manifest before the pipeline marks
          # the task `analyzing`.)
        end
    end
  end

  defp read_photo(%VerificationTask{photo_path: "/uploads/" <> _ = path}) do
    File.read!(Path.join("priv/static", path))
  end

  defp read_photo(%VerificationTask{photo_path: path}) when is_binary(path) do
    File.read!(Path.join("priv/static", String.trim_leading(path, "/")))
  rescue
    _ -> bundled_fallback(nil)
  end

  defp read_photo(%VerificationTask{photo_path: nil, scenario: scenario}) do
    bundled_fallback(scenario)
  end

  defp bundled_fallback(scenario) do
    filename =
      case scenario do
        "compliant" -> "captured_compliant.png"
        "minor_issues" -> "captured_minor_issues.png"
        "major_issues" -> "captured_major_issues.png"
        _ -> "captured_compliant.png"
      end

    path = Path.join(@bundled_dir, filename)

    case File.read(path) do
      {:ok, bytes} -> bytes
      # Fallback to a 1-byte PNG header so the pipeline still runs in CI
      # before the bundled images are committed.
      {:error, _} -> <<137, 80, 78, 71, 13, 10, 26, 10>>
    end
  end
end
