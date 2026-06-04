defmodule Showcase.Repo.Migrations.CreateRecruitFlowSchemas do
  use Ecto.Migration

  def change do
    create table(:rf_positions) do
      add :title, :string, null: false
      add :department, :string
      add :prompt_section, :string, null: false
      add :default_prompt_body, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rf_positions, [:title])

    create table(:rf_candidates) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rf_candidates, [:email])
    create index(:rf_candidates, [:phone])

    create table(:rf_applications) do
      add :candidate_id, references(:rf_candidates, on_delete: :delete_all), null: false
      add :position_id, references(:rf_positions, on_delete: :nilify_all)
      add :state, :string, null: false, default: "PENDING_CALL"
      add :transcript, :text
      add :eval, :map, default: %{}
      add :state_changed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rf_applications, [:candidate_id, :position_id])
    create index(:rf_applications, [:state])

    create table(:rf_cvs) do
      add :application_id, references(:rf_applications, on_delete: :delete_all)
      add :candidate_email, :string
      add :candidate_phone, :string
      add :subject_line, :string
      add :pdf_text, :text, null: false
      add :received_at, :utc_datetime_usec, null: false
      add :match_step, :string
      add :match_confidence, :float
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rf_cvs, [:application_id])
    create index(:rf_cvs, [:received_at])
  end
end
