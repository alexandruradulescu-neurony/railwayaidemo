defmodule Showcase.RestaurantCompliance.VisionPipeline do
  @moduledoc """
  Boundary for the Restaurant Compliance vision call.

      inspection (pending)
        → mark analyzing
        → read photo bytes + ref bytes
        → build VisionRequest
        → AnthropicClient.call
        → ResilientJSONParser.parse
        → persist result + usage, mark complete
        → broadcast {:restaurant_compliance, :complete, inspection_id}

  Failures (no photos / Anthropic error / parse fail) mark the inspection
  `failed` with an `error_reason` and broadcast `{:restaurant_compliance,
  :failed, inspection_id, reason}`.
  """

  alias Showcase.Common.{AnthropicClient, ResilientJSONParser}
  alias Showcase.RestaurantCompliance.{Inspection, Impl.VisionRequest}
  alias Showcase.Repo

  require Logger

  @topic_prefix "restaurant_compliance:inspection"

  @spec analyze(Inspection.t(), keyword()) ::
          {:ok, Inspection.t()} | {:error, term()}
  def analyze(%Inspection{} = inspection, opts) do
    photo_bytes_list = Keyword.get(opts, :photo_bytes_list, [])
    reference_bytes_list = Keyword.get(opts, :reference_bytes_list, [])
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    scenario = Keyword.get(opts, :scenario, "mixed")

    inspection = inspection |> Repo.preload(:ruleset)

    with :ok <- ensure_photos(photo_bytes_list),
         {:ok, inspection} <- mark_analyzing(inspection),
         _ <- broadcast(inspection.id, {:restaurant_compliance, :analyzing, inspection.id}),
         {:ok, raw_response} <-
           call_vision(inspection, photo_bytes_list, reference_bytes_list, scenario, max_tokens),
         {:ok, decoded, partial?} <- parse_response(raw_response.text),
         {:ok, inspection} <- mark_complete(inspection, decoded, raw_response.usage, partial?) do
      broadcast(inspection.id, {:restaurant_compliance, :complete, inspection.id})
      {:ok, inspection}
    else
      {:error, reason} = err ->
        Logger.error(
          "RestaurantCompliance.VisionPipeline failed for inspection #{inspection.id}: #{inspect(reason)}"
        )

        mark_failed(inspection, format_reason(reason))

        broadcast(
          inspection.id,
          {:restaurant_compliance, :failed, inspection.id, format_reason(reason)}
        )

        err
    end
  end

  defp ensure_photos([]), do: {:error, :no_photos_attached}
  defp ensure_photos(list) when is_list(list), do: :ok

  defp mark_analyzing(inspection) do
    inspection
    |> Inspection.changeset(%{status: "analyzing"})
    |> Repo.update()
  end

  defp call_vision(inspection, photo_bytes_list, reference_bytes_list, scenario, max_tokens) do
    ruleset = %{
      name: inspection.ruleset.name,
      rules_text: inspection.ruleset.rules_text
    }

    opts = [scenario: scenario, max_tokens: max_tokens]
    request = VisionRequest.build(ruleset, photo_bytes_list, reference_bytes_list, opts)

    AnthropicClient.call(request)
  end

  defp parse_response(text) do
    case ResilientJSONParser.parse(text) do
      {:ok, decoded, :complete} -> {:ok, decoded, false}
      {:ok, decoded, :partial} -> {:ok, Map.put(decoded, "_partial", true), true}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  defp mark_complete(inspection, decoded, usage, _partial?) do
    inspection
    |> Inspection.changeset(%{
      status: "complete",
      result: decoded,
      usage: %{
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "cost_estimate_cents" => usage.cost_estimate_cents
      }
    })
    |> Repo.update()
  end

  defp mark_failed(inspection, reason) do
    inspection
    |> Inspection.changeset(%{status: "failed", error_reason: reason})
    |> Repo.update()
  end

  defp format_reason({:parse_failed, r}), do: "parse failed: #{inspect(r)}"
  defp format_reason(:no_photos_attached), do: "no inspection photos attached"
  defp format_reason(other), do: inspect(other)

  defp broadcast(inspection_id, msg) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, "#{@topic_prefix}:#{inspection_id}", msg)
  end

  @doc "Public topic name for an inspection, for LiveView subscription."
  @spec topic(integer()) :: String.t()
  def topic(inspection_id), do: "#{@topic_prefix}:#{inspection_id}"
end
