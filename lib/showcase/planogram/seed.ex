defmodule Showcase.Planogram.Seed do
  @moduledoc """
  Seeds 1 planogram (3-shelf snack display) + 3 verification tasks, one
  per scenario, with mixed due-dates to demonstrate Today / Tomorrow /
  Overdue bucketing.

  Idempotent: re-running yields the same baseline state.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.Planogram.{Planogram, VerificationTask, MobileHandoff}
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
      planogram = upsert_planogram()
      upsert_tasks(planogram)
    end)

    seed_system_prompts()

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

  defp upsert_planogram do
    case Repo.get_by(Planogram, name: "3-shelf snack display") do
      nil ->
        {:ok, pg} =
          Repo.insert(%Planogram{
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
          })

        pg

      existing ->
        existing
    end
  end

  defp upsert_tasks(planogram) do
    today = Date.utc_today()

    [
      %{store_name: "Downtown Mart", scenario: "compliant", due_date: today},
      %{store_name: "Westside Express", scenario: "minor_issues", due_date: Date.add(today, 1)},
      %{store_name: "Eastpark Grocery", scenario: "major_issues", due_date: Date.add(today, -2)}
    ]
    |> Enum.each(fn task_attrs ->
      case Repo.get_by(VerificationTask, store_name: task_attrs.store_name, planogram_id: planogram.id) do
        nil ->
          Repo.insert!(%VerificationTask{
            planogram_id: planogram.id,
            store_name: task_attrs.store_name,
            due_date: task_attrs.due_date,
            scenario: task_attrs.scenario,
            mobile_token: MobileHandoff.generate_token(),
            status: "pending"
          })

        _existing ->
          :ok
      end
    end)
  end
end
