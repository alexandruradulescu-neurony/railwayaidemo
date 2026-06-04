defmodule Showcase.RecruitFlow.Schemas.Cv do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_cvs" do
    field :candidate_email, :string
    field :candidate_phone, :string
    field :subject_line, :string
    field :pdf_text, :string
    field :received_at, :utc_datetime_usec
    field :match_step, :string
    field :match_confidence, :float

    belongs_to :application, Application, foreign_key: :application_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(cv, attrs) do
    cv
    |> cast(attrs, [:application_id, :candidate_email, :candidate_phone,
                    :subject_line, :pdf_text, :received_at,
                    :match_step, :match_confidence])
    |> validate_required([:pdf_text, :received_at])
  end
end
