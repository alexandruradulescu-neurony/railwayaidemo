defmodule Showcase.Planogram.Planogram do
  @moduledoc """
  Reference shelf layout. One row per planogram a Manager has authored.

  `expected_rows` is a JSONB document of shape:

      %{
        "rows" => [
          %{
            "name" => "Top shelf",
            "position" => 1,
            "products" => [
              %{"sku" => "SKU-001", "name" => "Coca-Cola 500ml", "qty" => 6}
            ]
          }
        ]
      }
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "pg_planograms" do
    field :name, :string
    field :description, :string
    field :reference_image_path, :string
    field :expected_rows, :map, default: %{"rows" => []}

    has_many :verification_tasks, Showcase.Planogram.VerificationTask, foreign_key: :planogram_id

    timestamps(type: :utc_datetime)
  end

  def changeset(planogram, attrs) do
    planogram
    |> cast(attrs, [:name, :description, :reference_image_path, :expected_rows])
    |> validate_required([:name, :reference_image_path])
    |> unique_constraint(:name)
  end
end
