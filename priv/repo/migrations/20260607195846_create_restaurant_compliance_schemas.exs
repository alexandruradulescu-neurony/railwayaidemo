defmodule Showcase.Repo.Migrations.CreateRestaurantComplianceSchemas do
  use Ecto.Migration

  def change do
    create table(:rc_rulesets) do
      add :name, :string, null: false
      add :description, :text
      # The structured rules document the manager pastes.
      add :rules_text, :text, null: false
      # JSONB: %{"paths" => ["/images/restaurant_compliance/...", ...]}
      add :reference_image_paths, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:rc_rulesets, [:name])

    create table(:rc_inspections) do
      add :ruleset_id, references(:rc_rulesets, on_delete: :delete_all), null: false
      add :restaurant_name, :string, null: false
      add :inspector_name, :string
      add :due_date, :date, null: false
      add :status, :string, null: false, default: "pending"
      # JSONB: %{"paths" => ["/uploads/restaurant_compliance/...", ...]}
      add :photo_paths, :map, null: false, default: %{}
      # vision result JSON, nil until complete
      add :result, :map
      # %{input_tokens, output_tokens, cost_estimate_cents}, nil until complete
      add :usage, :map
      add :error_reason, :text
      timestamps(type: :utc_datetime)
    end

    create index(:rc_inspections, [:ruleset_id])
    create index(:rc_inspections, [:status])
    create index(:rc_inspections, [:due_date])
  end
end
