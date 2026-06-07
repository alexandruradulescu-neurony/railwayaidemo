defmodule Showcase.RestaurantCompliance.Worker do
  @moduledoc """
  Oban worker for the Restaurant Compliance vision pipeline.

  Args: `%{"inspection_id" => integer}`.

  Reads ALL reference images from disk (paths in
  `ruleset.reference_image_paths["paths"]`) and ALL inspection photos
  (paths in `inspection.photo_paths["paths"]`), then hands off to
  `VisionPipeline.analyze/2`. References are optional; inspection photos
  are required (pipeline fails with `:no_photos_attached` if none).
  """

  use Oban.Worker, queue: :restaurant_compliance, max_attempts: 3

  alias Showcase.RestaurantCompliance.{Inspection, VisionPipeline}
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inspection_id" => inspection_id}}) do
    case Repo.get(Inspection, inspection_id) |> Repo.preload(:ruleset) do
      nil ->
        {:error, :inspection_not_found}

      inspection ->
        photo_bytes_list = read_photo_list(inspection)
        reference_bytes_list = read_reference_list(inspection)

        opts = [
          photo_bytes_list: photo_bytes_list,
          reference_bytes_list: reference_bytes_list
        ]

        case VisionPipeline.analyze(inspection, opts) do
          {:ok, _} -> :ok
          # Pipeline already marked failed + broadcast. Don't retry on
          # parse/no-photo errors — swallow to keep Oban quiet.
          {:error, _} -> :ok
        end
    end
  end

  # ── Inspection photos ──────────────────────────────────────────────

  defp read_photo_list(%Inspection{photo_paths: %{"paths" => paths}}) when is_list(paths) do
    paths
    |> Enum.map(&safe_read/1)
    |> Enum.reject(&is_nil/1)
  end

  defp read_photo_list(_), do: []

  # ── Reference images (optional) ────────────────────────────────────

  defp read_reference_list(%Inspection{ruleset: %{reference_image_paths: %{"paths" => paths}}})
       when is_list(paths) do
    paths
    |> Enum.map(&safe_read_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp read_reference_list(_), do: []

  defp safe_read(nil), do: nil

  defp safe_read(path) when is_binary(path) do
    full = Path.join("priv/static", String.trim_leading(path, "/"))

    case File.read(full) do
      {:ok, bytes} when byte_size(bytes) > 100 -> bytes
      _ -> nil
    end
  end

  defp safe_read_ref(path) when is_binary(path) do
    # References are optional and may not exist on disk (e.g. before the
    # user drops the bundled placeholders in). Tolerate missing files.
    full = Path.join("priv/static", String.trim_leading(path, "/"))

    case File.read(full) do
      {:ok, bytes} when byte_size(bytes) > 100 -> bytes
      _ -> nil
    end
  end

  defp safe_read_ref(_), do: nil
end
