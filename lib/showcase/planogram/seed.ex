defmodule Showcase.Planogram.Seed do
  @moduledoc """
  Planogram demo seed. Intentionally minimal — the AE creates planograms
  and verification tasks live during the demo via the Manager view + the
  mobile capture flow.

  What this seed does:
    * Clears the upload directory (`/uploads/planogram/`) so old shelf
      photos don't carry over between demos.
    * Registers the vision system prompt (so `/admin/system-prompts`
      surfaces it).

  What it intentionally does NOT do:
    * Insert example planograms.
    * Insert verification tasks.

  Rationale: the operator creates real planograms + tasks with real images
  at demo time. Pre-seeded fixtures with placeholder images create a
  confusing visual mismatch (1×1 transparent PNGs that look broken).
  """

  @behaviour Showcase.Common.DemoSeeder

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
    seed_system_prompts()
    :ok
  end

  @doc """
  Test-only helper: inserts a baseline planogram + 3 verification tasks
  (one per scenario) so the existing test suite doesn't have to author
  fixtures per test. The production demo seed (`seed/0`) intentionally
  does NOT call this — empty inbox in front of the prospect.
  """
  def seed_test_fixtures do
    alias Showcase.Planogram.{Planogram, VerificationTask, MobileHandoff}
    alias Showcase.Repo

    Repo.transaction(fn ->
      planogram = upsert_planogram(Planogram, Repo)
      upsert_tasks(planogram, VerificationTask, MobileHandoff, Repo)
    end)

    :ok
  end

  defp seed_system_prompts do
    Showcase.Common.SystemPromptSeeder.upsert(
      "planogram",
      "vision_audit",
      Showcase.Planogram.Impl.VisionRequest.system_prompt(),
      note: "Vision call: audits shelf photo against expected planogram rows."
    )
  end

  defp clear_uploads do
    upload_dir = "priv/static/uploads/planogram"
    File.rm_rf!(upload_dir)
    File.mkdir_p!(upload_dir)
  end

  defp upsert_planogram(planogram_mod, repo) do
    case repo.get_by(planogram_mod, name: "3-shelf snack display") do
      nil ->
        {:ok, pg} =
          repo.insert(struct(planogram_mod, %{
            name: "3-shelf snack display",
            description: "Standard 3-shelf endcap for soft drinks. Top: Coca-Cola. Middle: Sprite + Fanta. Bottom: Pepsi.",
            reference_image_path: "/images/planogram/reference_3-shelf-snacks.png",
            expected_rows: %{
              "rows" => [
                %{"name" => "Top shelf", "position" => 1,
                  "products" => [%{"sku" => "S1", "name" => "Coca-Cola 500ml", "qty" => 6}]},
                %{"name" => "Middle shelf", "position" => 2,
                  "products" => [
                    %{"sku" => "S2", "name" => "Sprite 500ml", "qty" => 5},
                    %{"sku" => "S3", "name" => "Fanta 500ml", "qty" => 4}
                  ]},
                %{"name" => "Bottom shelf", "position" => 3,
                  "products" => [%{"sku" => "S4", "name" => "Pepsi 500ml", "qty" => 6}]}
              ]
            }
          }))

        pg

      existing ->
        existing
    end
  end

  defp upsert_tasks(planogram, task_mod, handoff_mod, repo) do
    today = Date.utc_today()

    [
      %{store_name: "Downtown Mart", scenario: "compliant", due_date: today},
      %{store_name: "Westside Express", scenario: "minor_issues", due_date: Date.add(today, 1)},
      %{store_name: "Eastpark Grocery", scenario: "major_issues", due_date: Date.add(today, -2)}
    ]
    |> Enum.each(fn task_attrs ->
      case repo.get_by(task_mod, store_name: task_attrs.store_name, planogram_id: planogram.id) do
        nil ->
          repo.insert!(struct(task_mod, %{
            planogram_id: planogram.id,
            store_name: task_attrs.store_name,
            due_date: task_attrs.due_date,
            scenario: task_attrs.scenario,
            mobile_token: handoff_mod.generate_token(),
            status: "pending"
          }))

        _existing ->
          :ok
      end
    end)
  end
end
