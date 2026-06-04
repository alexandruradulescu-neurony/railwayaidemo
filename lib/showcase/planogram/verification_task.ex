defmodule Showcase.Planogram.VerificationTask do
  @moduledoc """
  An audit row: planogram + store + due date + (eventually) captured photo + result.

  Status values:
    * `"pending"`   — created, no photo captured yet, OR photo captured but analysis not started
    * `"analyzing"` — Oban worker running the vision call
    * `"complete"`  — vision call succeeded (possibly with :partial JSON salvage)
    * `"failed"`    — vision call failed after retries (Anthropic 5xx, etc.)

  Overdue is NOT a status — it's a computed field via `Showcase.Planogram.Impl.Overdue.overdue?/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending analyzing complete failed)

  schema "pg_verification_tasks" do
    field :store_name, :string
    field :due_date, :date
    field :status, :string, default: "pending"
    field :photo_path, :string
    field :mobile_token, :string
    field :scenario, :string, default: "compliant"
    field :result, :map
    field :usage, :map
    field :error_reason, :string

    belongs_to :planogram, Showcase.Planogram.Planogram

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :planogram_id,
      :store_name,
      :due_date,
      :status,
      :photo_path,
      :mobile_token,
      :scenario,
      :result,
      :usage,
      :error_reason
    ])
    |> validate_required([:planogram_id, :store_name, :due_date, :mobile_token, :scenario])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:mobile_token)
    |> assoc_constraint(:planogram)
  end

  def valid_statuses, do: @valid_statuses
end
