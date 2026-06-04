defmodule Showcase.RecruitFlow.Schemas.Candidate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_candidates" do
    field :name, :string
    field :email, :string
    field :phone, :string

    has_many :applications, Application, foreign_key: :candidate_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:name, :email, :phone])
    |> validate_required([:name])
  end
end
