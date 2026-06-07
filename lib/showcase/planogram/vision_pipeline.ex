defmodule Showcase.Planogram.VisionPipeline do
  @moduledoc """
  Boundary module. Owns the single rich vision call:

      task (pending)
        → mark analyzing
        → read photo bytes
        → build VisionRequest
        → AnthropicClient.call
        → ResilientJSONParser.parse
        → persist result + usage, mark complete
        → broadcast {:planogram, :task_complete, task_id}

  Failures (no photo / Anthropic error) mark the task `failed` with an
  `error_reason` and broadcast `{:planogram, :task_failed, task_id, reason}`.
  """

  alias Showcase.Common.{AnthropicClient, ResilientJSONParser}
  alias Showcase.Planogram.{VerificationTask, Impl.VisionRequest}
  alias Showcase.Repo

  require Logger

  @topic_prefix "planogram:task"

  @spec analyze(VerificationTask.t(), keyword()) ::
          {:ok, VerificationTask.t()} | {:error, term()}
  def analyze(%VerificationTask{} = task, opts) do
    photo_bytes = Keyword.get(opts, :photo_bytes)
    reference_bytes = Keyword.get(opts, :reference_bytes)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    task = task |> Repo.preload(:planogram)

    with :ok <- ensure_photo(photo_bytes),
         {:ok, task} <- mark_analyzing(task),
         _ <- broadcast(task.id, {:planogram, :task_analyzing, task.id}),
         {:ok, raw_response} <- call_vision(task, photo_bytes, reference_bytes, max_tokens),
         {:ok, decoded, partial?} <- parse_response(raw_response.text),
         {:ok, task} <- mark_complete(task, decoded, raw_response.usage, partial?) do
      broadcast(task.id, {:planogram, :task_complete, task.id})
      {:ok, task}
    else
      {:error, reason} = err ->
        Logger.error("VisionPipeline.analyze failed for task #{task.id}: #{inspect(reason)}")
        mark_failed(task, format_reason(reason))
        broadcast(task.id, {:planogram, :task_failed, task.id, format_reason(reason)})
        err
    end
  end

  defp ensure_photo(nil), do: {:error, :no_photo_attached}
  defp ensure_photo(bytes) when is_binary(bytes), do: :ok

  defp mark_analyzing(task) do
    task
    |> VerificationTask.changeset(%{status: "analyzing"})
    |> Repo.update()
  end

  defp call_vision(task, photo_bytes, reference_bytes, max_tokens) do
    planogram = %{
      name: task.planogram.name,
      expected_rows: task.planogram.expected_rows
    }

    opts =
      [scenario: task.scenario, max_tokens: max_tokens]
      |> maybe_put(:reference_bytes, reference_bytes)

    request = VisionRequest.build(planogram, photo_bytes, opts)

    AnthropicClient.call(request)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_response(text) do
    case ResilientJSONParser.parse(text) do
      {:ok, decoded, :complete} -> {:ok, decoded, false}
      {:ok, decoded, :partial} -> {:ok, Map.put(decoded, "_partial", true), true}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  defp mark_complete(task, decoded, usage, _partial?) do
    task
    |> VerificationTask.changeset(%{
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

  defp mark_failed(task, reason) do
    task
    |> VerificationTask.changeset(%{status: "failed", error_reason: reason})
    |> Repo.update()
  end

  defp format_reason({:parse_failed, r}), do: "parse failed: #{inspect(r)}"
  defp format_reason(:no_photo_attached), do: "no photo attached"
  defp format_reason(other), do: inspect(other)

  defp broadcast(task_id, msg) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, "#{@topic_prefix}:#{task_id}", msg)
  end

  @doc "Public topic name for a task, exposed for LiveViews to subscribe."
  @spec topic(integer()) :: String.t()
  def topic(task_id), do: "#{@topic_prefix}:#{task_id}"
end
