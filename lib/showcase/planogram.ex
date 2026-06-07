defmodule Showcase.Planogram do
  @moduledoc """
  Public boundary for the Planogram Manager demo.

  Read paths (list_tasks, get_task, list_planograms) are plain Ecto.
  Write paths that enqueue Oban jobs (enqueue_analysis/1) live here.
  """

  import Ecto.Query

  alias Showcase.Planogram.{Planogram, VerificationTask, Worker, MobileHandoff, Impl.Overdue}
  alias Showcase.Repo

  @refs_dir "priv/static/images/planogram/refs"

  @spec list_tasks() :: list(VerificationTask.t())
  def list_tasks do
    from(t in VerificationTask, preload: [:planogram], order_by: [asc: t.due_date])
    |> Repo.all()
  end

  @spec get_task!(integer()) :: VerificationTask.t()
  def get_task!(id) do
    VerificationTask
    |> Repo.get!(id)
    |> Repo.preload(:planogram)
  end

  @spec list_planograms() :: list(Planogram.t())
  def list_planograms do
    Repo.all(from p in Planogram, order_by: [asc: p.name])
  end

  @spec bucket_tasks(Date.t()) :: map()
  def bucket_tasks(today \\ Date.utc_today()) do
    list_tasks() |> Overdue.bucket(today)
  end

  @doc """
  Enqueue an analysis job for the given task. Optional `:max_tokens` for
  the force-truncation demo.
  """
  @spec enqueue_analysis(integer(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_analysis(task_id, opts \\ []) do
    args = %{"task_id" => task_id}

    args =
      case Keyword.get(opts, :max_tokens) do
        nil -> args
        n when is_integer(n) -> Map.put(args, "max_tokens", n)
      end

    args |> Worker.new() |> Oban.insert()
  end

  @doc """
  Create a manager-authored task. Used by the Manager view.
  """
  @spec create_task(map()) :: {:ok, VerificationTask.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    attrs =
      attrs
      |> Map.put_new("mobile_token", Showcase.Planogram.MobileHandoff.generate_token())
      |> Map.put_new("status", "pending")

    %VerificationTask{}
    |> VerificationTask.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create a planogram from manager-supplied attrs + an uploaded reference image.

  Writes the bytes to `priv/static/images/planogram/refs/<unique>.<ext>` and
  stores the URL-relative path on the row. Returns the inserted planogram on
  success.
  """
  @spec create_planogram_with_reference(map(), binary()) ::
          {:ok, Planogram.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_planogram_with_reference(attrs, image_bytes) when is_binary(image_bytes) do
    File.mkdir_p!(@refs_dir)
    extension = extension_from_bytes(image_bytes)
    filename = "ref-#{System.unique_integer([:positive])}#{extension}"
    full_path = Path.join(@refs_dir, filename)
    File.write!(full_path, image_bytes)

    relative = "/images/planogram/refs/#{filename}"

    attrs =
      attrs
      |> normalize_keys()
      |> Map.put("reference_image_path", relative)

    %Planogram{}
    |> Planogram.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Save an uploaded shelf photo for an existing task. Delegates to
  `MobileHandoff.finalize_upload/2` — same on-disk layout as the mobile
  capture path.
  """
  @spec save_shelf_photo(VerificationTask.t(), binary()) ::
          {:ok, VerificationTask.t()} | {:error, Ecto.Changeset.t()}
  def save_shelf_photo(%VerificationTask{} = task, image_bytes) when is_binary(image_bytes) do
    MobileHandoff.finalize_upload(task, image_bytes)
  end

  # ── helpers ───────────────────────────────────────────────────────────

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
