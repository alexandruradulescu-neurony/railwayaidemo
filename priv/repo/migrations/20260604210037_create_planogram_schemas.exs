defmodule Showcase.Repo.Migrations.CreatePlanogramSchemas do
  use Ecto.Migration

  def change do
    create table(:pg_planograms) do
      add :name, :string, null: false
      add :description, :text
      add :reference_image_path, :string, null: false
      # JSONB of expected rows: [%{name, position, products: [%{sku, name, qty}]}, ...]
      add :expected_rows, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pg_planograms, [:name])

    create table(:pg_verification_tasks) do
      add :planogram_id, references(:pg_planograms, on_delete: :delete_all), null: false
      add :store_name, :string, null: false
      add :due_date, :date, null: false
      add :status, :string, null: false, default: "pending"
      # filesystem path under priv/static/ (nil until photo captured)
      add :photo_path, :string
      # single-use mobile-handoff token, unique
      add :mobile_token, :string, null: false
      # canned scenario tag used by Mock + bundled seed photos
      add :scenario, :string, null: false, default: "compliant"
      # vision call result (rich JSON from Claude), nil until complete
      add :result, :map
      # %{input_tokens, output_tokens, cost_estimate_cents}, nil until complete
      add :usage, :map
      add :error_reason, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pg_verification_tasks, [:mobile_token])
    create index(:pg_verification_tasks, [:planogram_id])
    create index(:pg_verification_tasks, [:status])
    create index(:pg_verification_tasks, [:due_date])
  end
end
