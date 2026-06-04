defmodule Showcase.InvoiceApproval.Worker do
  @moduledoc """
  Oban worker on `:invoice_approval` queue.
  """

  use Oban.Worker, queue: :invoice_approval, max_attempts: 3

  alias Showcase.InvoiceApproval.Pipeline
  alias Showcase.InvoiceApproval.Schemas.DocumentBundle
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bundle_id" => bundle_id}}) do
    case Repo.get(DocumentBundle, bundle_id) do
      nil ->
        {:error, :not_found}

      %DocumentBundle{} = bundle ->
        case Pipeline.process_bundle(bundle, %{now: DateTime.utc_now()}) do
          {:ok, _verdict} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
