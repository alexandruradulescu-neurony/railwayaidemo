defmodule Showcase.RestaurantCompliance do
  @moduledoc """
  Public boundary for the Restaurant Compliance demo.

  Read paths are plain Ecto. Write paths that touch disk + enqueue Oban
  jobs (`enqueue_analysis/1`, `save_inspection_photo/2`,
  `create_ruleset_with_references/2`) live here.
  """

  import Ecto.Query

  alias Showcase.RestaurantCompliance.{Ruleset, Inspection, Worker}
  alias Showcase.Repo

  @refs_dir "priv/static/images/restaurant_compliance"
  @uploads_dir "priv/static/uploads/restaurant_compliance"

  # ── Rulesets ───────────────────────────────────────────────────────

  @spec list_rulesets() :: list(Ruleset.t())
  def list_rulesets do
    Repo.all(from r in Ruleset, order_by: [asc: r.name])
  end

  @spec get_ruleset!(integer()) :: Ruleset.t()
  def get_ruleset!(id), do: Repo.get!(Ruleset, id)

  @doc """
  Create a ruleset with N reference images uploaded by the manager.

  `image_bytes_list` is a list of binaries; each is written to
  `priv/static/images/restaurant_compliance/<unique>.<ext>` and the
  relative URL is stored on the ruleset row.
  """
  @spec create_ruleset_with_references(map(), list(binary())) ::
          {:ok, Ruleset.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_ruleset_with_references(attrs, image_bytes_list)
      when is_list(image_bytes_list) do
    File.mkdir_p!(@refs_dir)

    paths =
      Enum.map(image_bytes_list, fn bytes ->
        ext = extension_from_bytes(bytes)
        filename = "ref-#{System.unique_integer([:positive])}#{ext}"
        full = Path.join(@refs_dir, filename)
        File.write!(full, bytes)
        "/images/restaurant_compliance/#{filename}"
      end)

    attrs =
      attrs
      |> normalize_keys()
      |> Map.put("reference_image_paths", %{"paths" => paths})

    %Ruleset{}
    |> Ruleset.changeset(attrs)
    |> Repo.insert()
  end

  @spec delete_ruleset(integer()) :: {:ok, Ruleset.t()} | {:error, term()}
  def delete_ruleset(id) do
    case Repo.get(Ruleset, id) do
      nil ->
        {:error, :not_found}

      rs ->
        # Delete reference images that live under our refs dir; bundled
        # assets in priv/static/images/restaurant_compliance/ are also
        # under that dir but they tend to have human-readable names so
        # we don't filter — manager is intentionally removing them.
        for path <- Ruleset.reference_paths(rs) do
          File.rm(Path.join("priv/static", String.trim_leading(path, "/")))
        end

        # Inspections cascade via FK on_delete: :delete_all.
        Repo.delete(rs)
    end
  end

  # ── Inspections ────────────────────────────────────────────────────

  @spec list_inspections() :: list(Inspection.t())
  def list_inspections do
    from(i in Inspection, preload: [:ruleset], order_by: [asc: i.due_date])
    |> Repo.all()
  end

  @spec get_inspection!(integer()) :: Inspection.t()
  def get_inspection!(id) do
    Inspection |> Repo.get!(id) |> Repo.preload(:ruleset)
  end

  @spec create_inspection(map()) :: {:ok, Inspection.t()} | {:error, Ecto.Changeset.t()}
  def create_inspection(attrs) do
    attrs = Map.put_new(attrs, "status", "pending")

    %Inspection{}
    |> Inspection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Append an uploaded inspection photo to an existing Inspection. Writes
  bytes to `priv/static/uploads/restaurant_compliance/<unique>.<ext>` and
  pushes the URL onto `photo_paths["paths"]`.
  """
  @spec save_inspection_photo(Inspection.t(), binary()) ::
          {:ok, Inspection.t()} | {:error, Ecto.Changeset.t()}
  def save_inspection_photo(%Inspection{} = inspection, image_bytes)
      when is_binary(image_bytes) do
    File.mkdir_p!(@uploads_dir)
    ext = extension_from_bytes(image_bytes)
    filename = "insp-#{inspection.id}-#{System.unique_integer([:positive])}#{ext}"
    full = Path.join(@uploads_dir, filename)
    File.write!(full, image_bytes)
    relative = "/uploads/restaurant_compliance/#{filename}"

    existing = Inspection.photo_paths(inspection)
    new_paths = existing ++ [relative]

    inspection
    |> Inspection.changeset(%{photo_paths: %{"paths" => new_paths}})
    |> Repo.update()
  end

  @spec enqueue_analysis(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_analysis(inspection_id) do
    %{"inspection_id" => inspection_id} |> Worker.new() |> Oban.insert()
  end

  @spec delete_inspection(integer()) :: {:ok, Inspection.t()} | {:error, term()}
  def delete_inspection(id) do
    case Repo.get(Inspection, id) do
      nil -> {:error, :not_found}
      i -> Repo.delete(i)
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  @doc false
  @spec extension_from_bytes(binary()) :: String.t()
  def extension_from_bytes(<<137, 80, 78, 71, _::binary>>), do: ".png"
  def extension_from_bytes(<<0xFF, 0xD8, 0xFF, _::binary>>), do: ".jpg"
  def extension_from_bytes(<<"GIF87a", _::binary>>), do: ".gif"
  def extension_from_bytes(<<"GIF89a", _::binary>>), do: ".gif"
  def extension_from_bytes(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: ".webp"
  def extension_from_bytes(_), do: ".jpg"
end
