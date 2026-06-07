defmodule Showcase.RestaurantCompliance.Ruleset do
  @moduledoc """
  A compliance ruleset authored by a manager: the rules document (free text)
  plus a list of reference standard images (mise-en-place guides) that the
  inspector's photos will be compared against.

  `reference_image_paths` is a JSONB of shape `%{"paths" => [<url>, ...]}` —
  same pattern as `Inspection.photo_paths` so the LiveView templates only
  deal with one container shape.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "rc_rulesets" do
    field :name, :string
    field :description, :string
    field :rules_text, :string
    field :reference_image_paths, :map, default: %{"paths" => []}

    has_many :inspections, Showcase.RestaurantCompliance.Inspection,
      foreign_key: :ruleset_id

    timestamps(type: :utc_datetime)
  end

  def changeset(ruleset, attrs) do
    ruleset
    |> cast(attrs, [:name, :description, :rules_text, :reference_image_paths])
    |> validate_required([:name, :rules_text])
    |> unique_constraint(:name)
  end

  @doc "Convenience extractor — the list of reference image URLs."
  @spec reference_paths(t()) :: list(String.t())
  def reference_paths(%__MODULE__{reference_image_paths: %{"paths" => paths}})
      when is_list(paths),
      do: paths

  def reference_paths(_), do: []
end
