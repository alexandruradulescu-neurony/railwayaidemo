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
  alias Showcase.Planogram.{VerificationTask, Impl.VisionRequest, MockPrompts}
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
         {:ok, raw_response, source} <-
           call_vision(task, photo_bytes, reference_bytes, max_tokens),
         {:ok, decoded, partial?} <- parse_response(raw_response.text),
         {:ok, task} <- mark_complete(task, decoded, raw_response.usage, source, partial?) do
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

  # Seeded scenarios (compliant / minor_issues / major_issues) bypass the
  # real `AnthropicClient.call/1` entirely when the configured impl is
  # `Live` (operator running with `ANTHROPIC_API_KEY`). Two reasons:
  #
  #   1. Predictable demo — the AE shows "click → magic" without burning
  #      ~2¢ per click on real Claude tokens for canned shelf photos.
  #   2. Determinism — real Claude variance won't drift the score or
  #      surface a "partial" parse mid-pitch.
  #
  # When the impl is `Mock` (tests + dev with no API key), we go through
  # `AnthropicClient.call/1` so per-test `Mock.register` overrides (e.g.
  # the force-truncation test) still work. The Mock impl already serves
  # the same scripted responses via `MockPrompts.register_all/0`.
  #
  # Tasks created live via the Manager view have a scenario tag the
  # lookup doesn't recognize → falls through to real Claude either way.
  # Mirrors the OrderFlow + Invoice Approval pattern (REVIEW.md HI-01).
  defp call_vision(task, photo_bytes, reference_bytes, max_tokens) do
    cond do
      live_impl?() and match?({:ok, _}, MockPrompts.scripted_response_for(task.scenario)) ->
        {:ok, response} = MockPrompts.scripted_response_for(task.scenario)
        {:ok, response, "mock"}

      true ->
        planogram = %{
          name: task.planogram.name,
          expected_rows: task.planogram.expected_rows
        }

        opts =
          [scenario: task.scenario, max_tokens: max_tokens]
          |> maybe_put(:reference_bytes, reference_bytes)

        request = VisionRequest.build(planogram, photo_bytes, opts)

        case AnthropicClient.call(request) do
          {:ok, response} -> {:ok, response, "live"}
          {:error, _} = err -> err
        end
    end
  end

  defp live_impl? do
    Application.get_env(:showcase, :anthropic_client_impl) ==
      Showcase.Common.AnthropicClient.Live
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

  # `source` is "mock" for scripted scenarios (free) or "live" for real
  # Claude calls. The cost-badge UI uses it to render "(scripted)" or
  # gray out cost when the run didn't actually cost anything.
  defp mark_complete(task, decoded, usage, source, _partial?) do
    task
    |> VerificationTask.changeset(%{
      status: "complete",
      result: decoded,
      usage: %{
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "cost_estimate_cents" => usage.cost_estimate_cents,
        "source" => source
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
