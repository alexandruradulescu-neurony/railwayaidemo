defmodule Showcase.RestaurantCompliance.Inspection do
  @moduledoc """
  A single restaurant inspection — N photos uploaded by an inspector,
  compared against a Ruleset's rules document and reference images.

  Status values:
    * `"pending"`   — created (with or without photos), not analyzing yet
    * `"analyzing"` — vision call running
    * `"complete"`  — vision call returned a parsed result
    * `"failed"`    — vision call or parse failed after retries
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending analyzing complete failed)

  schema "rc_inspections" do
    field :restaurant_name, :string
    field :inspector_name, :string
    field :due_date, :date
    field :status, :string, default: "pending"
    field :photo_paths, :map, default: %{"paths" => []}
    field :result, :map
    field :usage, :map
    field :error_reason, :string

    belongs_to :ruleset, Showcase.RestaurantCompliance.Ruleset

    timestamps(type: :utc_datetime)
  end

  def changeset(inspection, attrs) do
    inspection
    |> cast(attrs, [
      :ruleset_id,
      :restaurant_name,
      :inspector_name,
      :due_date,
      :status,
      :photo_paths,
      :result,
      :usage,
      :error_reason
    ])
    |> validate_required([:ruleset_id, :restaurant_name, :due_date])
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:ruleset)
  end

  def valid_statuses, do: @valid_statuses

  @doc "Convenience extractor — list of inspection photo URLs."
  @spec photo_paths(t()) :: list(String.t())
  def photo_paths(%__MODULE__{photo_paths: %{"paths" => paths}}) when is_list(paths),
    do: paths

  def photo_paths(_), do: []
end
