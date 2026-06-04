defmodule Showcase.RecruitFlow.Schemas.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_positions" do
    field :title, :string
    field :department, :string
    field :prompt_section, :string
    field :default_prompt_body, :string

    has_many :applications, Application, foreign_key: :position_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:title, :department, :prompt_section, :default_prompt_body])
    |> validate_required([:title, :prompt_section])
    |> unique_constraint(:title)
  end
end
