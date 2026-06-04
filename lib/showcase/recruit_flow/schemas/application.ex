defmodule Showcase.RecruitFlow.Schemas.Application do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.{Candidate, Cv, Position}

  schema "rf_applications" do
    field :state, :string, default: "PENDING_CALL"
    field :transcript, :string
    field :eval, :map, default: %{}
    field :state_changed_at, :utc_datetime_usec

    belongs_to :candidate, Candidate, foreign_key: :candidate_id
    belongs_to :position, Position, foreign_key: :position_id
    has_many :cvs, Cv, foreign_key: :application_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, [:candidate_id, :position_id, :state, :transcript, :eval, :state_changed_at])
    |> validate_required([:candidate_id, :state, :state_changed_at])
    |> unique_constraint([:candidate_id, :position_id])
  end
end
