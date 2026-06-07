defmodule Showcase.Planogram.Seed do
  @moduledoc """
  Planogram demo seed. Inserts 2 reference planograms (pharmacy shelf +
  natural juices shelf) and 5 verification tasks (3 pharmacy + 2 juices,
  one per scenario: compliant / minor_issues / major_issues).

  Reference images must exist at:
    * `priv/static/images/planogram/pharmacy_shelf_reference.jpg`
    * `priv/static/images/planogram/natural_juices_reference.jpg`

  These are committed to the repo (not in the gitignored `refs/` dir).
  The AE attaches per-task shelf photos via the Merchandiser UI at demo
  time using their own test images (`priv/static/images/planogram/test-shelves/...`).
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.Planogram.{MobileHandoff, Planogram, VerificationTask}
  alias Showcase.Repo

  @impl true
  def name, do: "Planogram Manager"

  @impl true
  def description do
    "Retail shelf compliance via a single vision call. The system returns score, per-row breakdown, issues, and suggestions — in seconds, not afternoons."
  end

  @impl true
  def tables, do: ~w(pg_verification_tasks pg_planograms)

  @impl true
  def oban_queue, do: :planogram

  @impl true
  def seed do
    clear_uploads()

    Repo.transaction(fn ->
      pharmacy = upsert_planogram(pharmacy_attrs())
      juices = upsert_planogram(juices_attrs())
      upsert_tasks(pharmacy, juices)
    end)
    |> case do
      {:ok, _} ->
        seed_system_prompts()
        :ok

      {:error, reason} ->
        # Surface the failure so `Showcase.Common.Reset` can roll back the
        # outer Multi instead of pretending the demo reset succeeded.
        {:error, reason}
    end
  end

  # ── Pharmacy planogram ────────────────────────────────────────────────
  defp pharmacy_attrs do
    %{
      name: "Pharmacy OTC end-cap",
      description:
        "6-shelf pharmacy end-cap. Top: children's analgesics + antacids. Middle: adult pain relief, lozenges, topical creams. Bottom: digestive and supplements.",
      reference_image_path: "/images/planogram/pharmacy_shelf_reference.jpg",
      expected_rows: %{
        "rows" => [
          %{"name" => "Top shelf — Children's & antacids", "position" => 1,
            "products" => [
              %{"sku" => "NURJ-7", "name" => "Nurofen Junior 7+", "qty" => 6},
              %{"sku" => "NURJ-3", "name" => "Nurofen 3-12 ani", "qty" => 4},
              %{"sku" => "GAV", "name" => "Gaviscon sachets", "qty" => 4},
              %{"sku" => "RDX", "name" => "Redoxon Vitamin C", "qty" => 2}
            ]},
          %{"name" => "Shelf 2 — Adult pain relief", "position" => 2,
            "products" => [
              %{"sku" => "NURF", "name" => "Nurofen Forte", "qty" => 6},
              %{"sku" => "NUREXP", "name" => "Nurofen Express", "qty" => 6}
            ]},
          %{"name" => "Shelf 3 — Throat lozenges (Strepsils)", "position" => 3,
            "products" => [
              %{"sku" => "STREP-L", "name" => "Strepsils Lemon", "qty" => 6},
              %{"sku" => "STREP-H", "name" => "Strepsils Honey", "qty" => 4},
              %{"sku" => "STREP-I", "name" => "Strepsils Intensiv", "qty" => 4},
              %{"sku" => "STREP-M", "name" => "Strepsils Mentol", "qty" => 4}
            ]},
          %{"name" => "Shelf 4 — Topical creams", "position" => 4,
            "products" => [
              %{"sku" => "ALLE-GEL", "name" => "Allé Gel", "qty" => 4},
              %{"sku" => "ALLE-CRM", "name" => "Allé Cremă", "qty" => 2},
              %{"sku" => "ALLG", "name" => "Allego", "qty" => 2},
              %{"sku" => "GMX", "name" => "Gastimax Med", "qty" => 6}
            ]},
          %{"name" => "Shelf 5 — Pain gel + digestive", "position" => 5,
            "products" => [
              %{"sku" => "SIND", "name" => "Sindolor Gel", "qty" => 6},
              %{"sku" => "EMTX", "name" => "Emetix", "qty" => 4},
              %{"sku" => "DGXP", "name" => "Digex Plus", "qty" => 4}
            ]},
          %{"name" => "Bottom shelf — Supplements", "position" => 6,
            "products" => [
              %{"sku" => "MOLK", "name" => "Molekin", "qty" => 2},
              %{"sku" => "DETR", "name" => "Detrical 2000", "qty" => 2},
              %{"sku" => "OPTM", "name" => "Optisomn", "qty" => 2},
              %{"sku" => "MILK", "name" => "Milk Thistle Colina", "qty" => 2},
              %{"sku" => "SLBO", "name" => "Slabofit Slim", "qty" => 2},
              %{"sku" => "PROC", "name" => "Procalmum Cremă", "qty" => 2},
              %{"sku" => "VZK", "name" => "Vizik", "qty" => 2},
              %{"sku" => "CMGZ", "name" => "CaMgZn + Vitamina C", "qty" => 2}
            ]}
        ]
      }
    }
  end

  # ── Natural juices planogram ──────────────────────────────────────────
  defp juices_attrs do
    %{
      name: "Natural juices aisle",
      description:
        "5-shelf juices aisle. Top: premium cold-pressed singles. Then kids' tetra packs. Then family jugs. Cartons. Bottom: 3L vegetable juices.",
      reference_image_path: "/images/planogram/natural_juices_reference.jpg",
      expected_rows: %{
        "rows" => [
          %{"name" => "Top — Premium / specialty bottles", "position" => 1,
            "products" => [
              %{"sku" => "ANT-POM", "name" => "Antos Pomegranate 500ml", "qty" => 12},
              %{"sku" => "PURE-GR", "name" => "Pure Bloois Green Juice 500ml", "qty" => 12}
            ]},
          %{"name" => "Shelf 2 — Kids tetra packs", "position" => 2,
            "products" => [
              %{"sku" => "FP-APL", "name" => "Fruit Pal Apple 200ml", "qty" => 8},
              %{"sku" => "FP-GRP", "name" => "Fruit Pal Grape 200ml", "qty" => 8}
            ]},
          %{"name" => "Shelf 3 — Family jugs", "position" => 3,
            "products" => [
              %{"sku" => "SO-TRP", "name" => "Sun Orchard Tropical 1.5L", "qty" => 8},
              %{"sku" => "SO-ORG", "name" => "Sun Orchard Orange 1.5L", "qty" => 8}
            ]},
          %{"name" => "Shelf 4 — Cartons", "position" => 4,
            "products" => [
              %{"sku" => "HG-ORG", "name" => "Harvest Grove Orange 1L", "qty" => 10},
              %{"sku" => "HG-APL", "name" => "Harvest Grove Apple 1L", "qty" => 10}
            ]},
          %{"name" => "Bottom — 3L vegetable", "position" => 5,
            "products" => [
              %{"sku" => "GE-TOM", "name" => "Garden Essence Tomato 3L", "qty" => 8},
              %{"sku" => "GE-VEG", "name" => "Garden Essence Vegetable 3L", "qty" => 8}
            ]}
        ]
      }
    }
  end

  defp upsert_planogram(attrs) do
    case Repo.get_by(Planogram, name: attrs.name) do
      nil ->
        {:ok, pg} = Repo.insert(struct(Planogram, attrs))
        pg

      existing ->
        existing
    end
  end

  defp upsert_tasks(pharmacy, juices) do
    today = Date.utc_today()

    [
      # Pharmacy: 3 scenarios
      %{planogram_id: pharmacy.id, store_name: "Farmacia Tei Centru", scenario: "compliant", due_date: today},
      %{planogram_id: pharmacy.id, store_name: "Sensiblu Băneasa", scenario: "minor_issues", due_date: today},
      %{planogram_id: pharmacy.id, store_name: "Catena Plaza", scenario: "major_issues", due_date: today},
      # Juices: 2 scenarios
      %{planogram_id: juices.id, store_name: "Hypermarket Băneasa", scenario: "compliant", due_date: today},
      %{planogram_id: juices.id, store_name: "Mega Image Centru", scenario: "major_issues", due_date: today}
    ]
    |> Enum.each(fn task_attrs ->
      case Repo.get_by(VerificationTask,
             store_name: task_attrs.store_name,
             planogram_id: task_attrs.planogram_id
           ) do
        nil ->
          Repo.insert!(
            struct(VerificationTask,
              Map.merge(task_attrs, %{
                mobile_token: MobileHandoff.generate_token(),
                status: "pending"
              })
            )
          )

        _existing ->
          :ok
      end
    end)
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "planogram",
      "vision_audit",
      Showcase.Planogram.Impl.VisionRequest.system_prompt(),
      note: "Vision call: audits shelf photo against expected planogram rows."
    )
  end

  # The filesystem is shared between :dev and :test (DB sandbox isolates
  # only the database). Running test seeds wiped the dev uploads dir,
  # leaving DB rows with broken photo_path values. Skip the wipe in test.
  # Mix.env() is resolved at COMPILE time so the test-env build never
  # carries the rm_rf call.
  if Mix.env() == :test do
    defp clear_uploads, do: :ok
  else
    defp clear_uploads do
      upload_dir = "priv/static/uploads/planogram"
      File.rm_rf!(upload_dir)
      File.mkdir_p!(upload_dir)
    end
  end
end
