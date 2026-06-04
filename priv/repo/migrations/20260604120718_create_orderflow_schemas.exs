defmodule Showcase.Repo.Migrations.CreateOrderflowSchemas do
  use Ecto.Migration

  def change do
    create table(:of_clients) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:of_clients, [:name])

    create table(:of_products) do
      add :sku, :string, null: false
      add :name, :string, null: false
      add :normalized_name, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:of_products, [:sku])
    create index(:of_products, [:normalized_name])

    create table(:of_product_aliases) do
      add :normalized_text, :string, null: false
      add :product_id, references(:of_products, on_delete: :delete_all), null: false
      add :client_id, references(:of_clients, on_delete: :delete_all)  # NULL = global
      add :confidence, :float, null: false, default: 0.5
      add :last_used_at, :utc_datetime_usec, null: false
      add :use_count, :integer, null: false, default: 1
      add :source, :string, null: false  # "correction" | "promotion" | "seed"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_product_aliases, [:normalized_text])
    create index(:of_product_aliases, [:client_id, :normalized_text])
    # gin index for pg_trgm similarity searches on normalized_text
    execute(
      "CREATE INDEX of_product_aliases_text_trgm_idx ON of_product_aliases USING GIN (normalized_text gin_trgm_ops)",
      "DROP INDEX IF EXISTS of_product_aliases_text_trgm_idx"
    )

    create table(:of_synthetic_messages) do
      add :body, :text, null: false
      add :kind, :string, null: false       # "email" | "whatsapp"
      add :scenario, :string, null: false   # matches AnthropicClient.Mock fingerprint+scenario
      add :client_hint, :string             # what the message hints about its sender
      timestamps(type: :utc_datetime_usec)
    end

    create table(:of_orders) do
      add :client_id, references(:of_clients, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending_review"
      add :synthetic_message_id, references(:of_synthetic_messages, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_orders, [:client_id])
    create index(:of_orders, [:status])

    create table(:of_order_lines) do
      add :order_id, references(:of_orders, on_delete: :delete_all), null: false
      add :product_id, references(:of_products, on_delete: :nilify_all)
      add :raw_description, :string, null: false
      add :quantity, :integer, null: false
      add :confidence, :float
      add :match_step, :string  # which cascade step matched ("exact", "fuzzy", etc.)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_order_lines, [:order_id])
  end
end
