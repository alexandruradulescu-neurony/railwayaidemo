defmodule Showcase.Repo.Migrations.AuditLogIndexes do
  use Ecto.Migration

  # Filter + sort go to the DB. Without these indexes a long-running deploy
  # with thousands of audit rows triggers a seq-scan on every filter+sort
  # call from AuditLogLive. See REVIEW.md MED-02.
  def change do
    create_if_not_exists index(:common_audit_logs, [:demo, :inserted_at])
    create_if_not_exists index(:common_audit_logs, [:demo, :entity_type, :entity_id])
  end
end
