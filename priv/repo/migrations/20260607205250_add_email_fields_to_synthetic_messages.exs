defmodule Showcase.Repo.Migrations.AddEmailFieldsToSyntheticMessages do
  use Ecto.Migration

  def change do
    alter table(:of_synthetic_messages) do
      add :from_address, :string
      add :subject, :string
      add :attachment_paths, {:array, :string}, default: [], null: false
      add :composed, :boolean, default: false, null: false
    end

    # Composed messages don't have a scripted scenario.
    alter table(:of_synthetic_messages) do
      modify :scenario, :string, null: true, from: {:string, null: false}
    end
  end
end
