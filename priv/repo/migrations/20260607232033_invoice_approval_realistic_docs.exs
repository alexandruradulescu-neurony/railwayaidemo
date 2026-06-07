defmodule Showcase.Repo.Migrations.InvoiceApprovalRealisticDocs do
  use Ecto.Migration

  def change do
    # Enrich Client with the bits an AP system needs to identify the sender
    # of an invoice email and pull the right contract.
    alter table(:ia_clients) do
      add :email, :string
      add :vat_number, :string
      add :address, :string
      add :country, :string, default: "RO"
    end

    create unique_index(:ia_clients, [:email])

    # Contracts get document-y metadata so the rendered "PDF" looks real.
    alter table(:ia_contracts) do
      add :contract_number, :string
      add :currency, :string, default: "RON"
    end

    # Bundles track their workflow status + uploaded file paths for the
    # invoice (received via email) and the aviz (uploaded by AP clerk).
    alter table(:ia_document_bundles) do
      add :status, :string, default: "pending", null: false
      add :invoice_path, :string
      add :aviz_path, :string
      add :composed, :boolean, default: false, null: false
    end

    create index(:ia_document_bundles, [:status])
  end
end
