defmodule Showcase.Common.SystemPrompt do
  @moduledoc """
  Live-editable LLM system prompt.

  Identified by `(demo, section)` — e.g. `("order_flow", "extraction")`.
  Versioned: every update writes a new row with `version + 1`; older
  versions are kept for inspection.

  The boundary code reads `latest/2` to fetch the currently-active prompt.
  """

  use Ash.Resource,
    domain: Showcase.Common,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "common_system_prompts"
    repo Showcase.Repo
  end

  attributes do
    integer_primary_key :id

    attribute :demo, :string do
      allow_nil? false
      public? true
      constraints max_length: 64
    end

    attribute :section, :string do
      allow_nil? false
      public? true
      constraints max_length: 64
    end

    attribute :version, :integer do
      allow_nil? false
      public? true
      default 1
    end

    attribute :body, :string do
      allow_nil? false
      public? true
    end

    attribute :note, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:demo, :section, :version, :body, :note]
    end

    update :update do
      accept [:body, :note]
    end

    read :latest do
      argument :demo, :string, allow_nil?: false
      argument :section, :string, allow_nil?: false

      prepare build(sort: [version: :desc], limit: 1)
      filter expr(demo == ^arg(:demo) and section == ^arg(:section))
    end
  end

  identities do
    identity :unique_demo_section_version, [:demo, :section, :version]
  end

  code_interface do
    define :latest, args: [:demo, :section], action: :latest
  end
end
