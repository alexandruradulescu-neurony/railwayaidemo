defmodule Showcase.Dashboard.Tile do
  @moduledoc """
  One entry in the dashboard tile registry.

  Tiles are declared in `Showcase.Dashboard.TileConfig` and exposed via the
  `Showcase.Dashboard` context.
  """

  @enforce_keys [:id, :title, :description, :roi_hook, :status]
  defstruct [
    :id,
    :title,
    :description,
    :roi_hook,
    :status,
    :path,
    :seeder
  ]

  @type status :: :live | :coming_soon

  @type t :: %__MODULE__{
          id: atom(),
          title: String.t(),
          description: String.t(),
          roi_hook: String.t(),
          status: status(),
          path: String.t() | nil,
          seeder: module() | nil
        }
end
