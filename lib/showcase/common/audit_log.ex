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
    defaults [:read]

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
  end

  code_interface do
    define :write, args: [:demo, :entity_type, :entity_id, :event]
    define :for_entity, args: [:demo, :entity_type, :entity_id]
  end
end
