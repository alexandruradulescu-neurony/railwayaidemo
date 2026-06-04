defmodule Showcase.Repo.Migrations.CreateInvoiceApprovalSchemas do
  use Ecto.Migration

  def change do
    create table(:ia_clients) do
      add :name, :string, null: false
      add :contact, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ia_clients, [:name])

    create table(:ia_contracts) do
      add :client_id, references(:ia_clients, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :body, :map, null: false, default: %{}
      add :default_thresholds, :map, null: false, default: %{}
      add :valid_from, :date
      add :valid_until, :date
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ia_contracts, [:client_id])

    create table(:ia_document_bundles) do
      add :client_id, references(:ia_clients, on_delete: :nilify_all)
      add :contract_id, references(:ia_contracts, on_delete: :nilify_all)
      add :scenario, :string, null: false
      add :kind, :string, null: false
      add :delivery_notes, :map, null: false, default: %{}
      add :invoice, :map, null: false, default: %{}
      add :thresholds, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ia_document_bundles, [:client_id])
    create index(:ia_document_bundles, [:scenario])

    create table(:ia_verdicts) do
      add :bundle_id, references(:ia_document_bundles, on_delete: :delete_all), null: false
      add :outcome, :string, null: false
      add :reasoning, :text, null: false
      add :raw_matrix, :map, null: false, default: %{}
      add :classified_matrix, :map, null: false, default: %{}
      add :thresholds_used, :map, null: false, default: %{}
      add :source, :string, null: false
      add :actor, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ia_verdicts, [:bundle_id, :inserted_at])
  end
end
