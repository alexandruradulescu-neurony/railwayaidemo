defmodule Showcase.RestaurantCompliance.Seed do
  @moduledoc """
  Seeds one Ruleset — "Mise-en-place standards" — with the verbatim
  policy text from the official compliance guide and two reference image
  paths. The bundled reference image files don't need to exist on disk;
  the Worker tolerates missing references and Claude still gets the
  rules text + inspection photos.

  No seed inspections — the user creates them live during the demo so
  the audience sees the create-inspection form in action.

  Idempotent: re-running yields the same baseline state.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.RestaurantCompliance.{Inspection, Ruleset, Impl.VisionRequest}
  alias Showcase.Repo

  @ruleset_name "Mise-en-place standards"

  # 3 believable Bucharest restaurants, each waiting on inspector photos.
  # The AE uploads the actual restaurant photos at demo time.
  @inspections [
    %{restaurant_name: "Caru' cu Bere", inspector_name: "Andrei Popescu"},
    %{restaurant_name: "Hanu' lui Manuc", inspector_name: "Maria Ionescu"},
    %{restaurant_name: "Bistro Ateneu", inspector_name: "Stefan Radu"}
  ]

  @impl true
  def name, do: "Restaurant Compliance"

  @impl true
  def description do
    "Checklist-driven compliance audits — rule-by-rule pass/fail against photo evidence. Replaces an inspector's afternoon with ~5¢ per visit."
  end

  @impl true
  def tables, do: ~w(rc_inspections rc_rulesets)

  @impl true
  def oban_queue, do: :restaurant_compliance

  @impl true
  def seed do
    clear_uploads()

    Repo.transaction(fn ->
      ruleset = upsert_ruleset()
      upsert_inspections(ruleset)
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

  defp upsert_inspections(ruleset) do
    today = Date.utc_today()

    Enum.each(@inspections, fn attrs ->
      case Repo.get_by(Inspection, restaurant_name: attrs.restaurant_name) do
        nil ->
          Repo.insert!(%Inspection{
            ruleset_id: ruleset.id,
            restaurant_name: attrs.restaurant_name,
            inspector_name: attrs.inspector_name,
            due_date: today,
            status: "pending",
            photo_paths: %{"paths" => []},
            result: %{},
            usage: %{}
          })

        _existing ->
          :ok
      end
    end)
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "restaurant_compliance",
      "vision_audit",
      VisionRequest.system_prompt(),
      note:
        "Vision call: rule-by-rule restaurant compliance audit against mise-en-place standards."
    )
  end

  # Filesystem is shared with :test (sandbox isolates DB only). Skip
  # the wipe in test env so the dev uploads dir survives `mix test`.
  # Mix.env() is resolved at COMPILE time.
  if Mix.env() == :test do
    defp clear_uploads, do: :ok
  else
    defp clear_uploads do
      upload_dir = "priv/static/uploads/restaurant_compliance"
      File.rm_rf!(upload_dir)
      File.mkdir_p!(upload_dir)
    end
  end

  defp upsert_ruleset do
    case Repo.get_by(Ruleset, name: @ruleset_name) do
      nil ->
        {:ok, rs} =
          Repo.insert(%Ruleset{
            name: @ruleset_name,
            description: "Top-down mise-en-place layout standard, courses + central elements + housekeeping.",
            rules_text: rules_text(),
            reference_image_paths: %{
              "paths" => [
                "/images/restaurant_compliance/reference_round_table_guide.jpg",
                "/images/restaurant_compliance/reference_two_person_guide.jpg"
              ]
            }
          })

        rs

      existing ->
        existing
    end
  end

  defp rules_text do
    """
    Official Mise en Place Compliance Guide:
    Viewpoint: Direct top-down, providing a clear layout of all settings.

    Central Elements:
    - Bottle Facings: Bottles on the lazy Susan are clean and face outward toward the diners.
    - Card Placement: A formalized red text card with specific standard instructions is centered.
    - Grinders: Polished salt and pepper grinders are in a specific, clean position.

    Place Settings:
    - Flatware: Knives are perfectly parallel to the right, forks to the left. All are aligned precisely with the plate.
    - Napkins: Clean, dark grey linen napkins are neatly folded on pristine white plates.
    - Glassware: Water, red, and white wine glasses are clean, polished, and arranged in a consistent pattern to the upper right of each setting.
    - Dishes: Clean side plates and bowls are set for courses.

    General:
    - Floor must be free of food debris, dirt, or fallen napkins.
    - Tables must be cleared and reset between services.
    - Empty bottles and used dishes must not be left on tables.
    """
  end
end
