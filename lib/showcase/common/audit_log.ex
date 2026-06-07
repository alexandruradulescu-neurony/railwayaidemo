defmodule Showcase.Common.AuditLog do
  @moduledoc """
  Append-only event store. Every demo writes to this table when something
  meaningful happens: state transitions (RecruitFlow), verdict overrides
  (Invoice), reset events, AI calls that failed, etc.

  Querying:
    * by `demo` and `entity_type` to scope to one demo's events
    * by `entity_id` to follow one entity through time
  """

  use Ash.Resource,
    domain: Showcase.Common,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "common_audit_logs"
    repo Showcase.Repo
  end

  attributes do
    integer_primary_key :id

    attribute :demo, :string do
      allow_nil? false
      public? true
    end

    attribute :entity_type, :string do
      allow_nil? false
      public? true
    end

    attribute :entity_id, :string do
      allow_nil? false
      public? true
    end

    attribute :event, :string do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      public? true
      default %{}
    end

    attribute :actor, :string, public?: true

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read, :destroy]

    create :write do
      accept [:demo, :entity_type, :entity_id, :event, :payload, :actor]
    end

    read :for_entity do
      argument :demo, :string, allow_nil?: false
      argument :entity_type, :string, allow_nil?: false
      argument :entity_id, :string, allow_nil?: false

      prepare build(sort: [inserted_at: :desc])
      filter expr(demo == ^arg(:demo) and entity_type == ^arg(:entity_type) and entity_id == ^arg(:entity_id))
    end

    # DB-side filter + sort + limit. The Ash.read! → Enum.filter pattern
    # in audit_log_live.ex pulled every row over the wire, which is fine
    # for demo loads (few dozen rows) but O(n) for a long-running deploy.
    # See REVIEW.md MED-02.
    read :list_recent do
      argument :demo, :string, allow_nil?: true
      argument :limit, :integer, default: 50

      prepare build(sort: [inserted_at: :desc])

      filter expr(if is_nil(^arg(:demo)), do: true, else: demo == ^arg(:demo))

      prepare fn query, _ctx ->
        limit = Ash.Query.get_argument(query, :limit)
        Ash.Query.limit(query, limit)
      end
    end
  end

  code_interface do
    define :write, args: [:demo, :entity_type, :entity_id, :event]
    define :for_entity, args: [:demo, :entity_type, :entity_id]
    define :list_recent
  end
end
