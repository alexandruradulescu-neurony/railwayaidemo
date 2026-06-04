defmodule Showcase.Common.AnthropicClient.Live do
  @moduledoc """
  Real Anthropic API impl. Uses `:anthropix` under the hood.

  Emits `[:showcase, :anthropic, :call]` telemetry on success and
  `[:showcase, :anthropic, :call_failed]` on errors.
  """

  @behaviour Showcase.Common.AnthropicClient

  require Logger

  alias Showcase.Common.AnthropicClient.Types.{Request, Response, Usage}

  # Pricing (cents per 1M tokens). Update as Anthropic publishes new tiers.
  # Sources: https://www.anthropic.com/pricing
  @pricing %{
    "claude-haiku-4-5-20251001" => %{input: 80, output: 400},
    "claude-sonnet-4-5" => %{input: 300, output: 1500}
  }

  @default_model "claude-haiku-4-5-20251001"

  @impl Showcase.Common.AnthropicClient
  def call(%Request{} = req, _opts) do
    start_time = System.monotonic_time(:millisecond)
    model = req.model || @default_model

    body = build_body(req, model)

    client = Anthropix.init(System.get_env("ANTHROPIC_API_KEY") || "")

    case Anthropix.chat(client, body) do
      {:ok, raw} ->
        duration = System.monotonic_time(:millisecond) - start_time
        response = build_response(raw, model)

        :telemetry.execute(
          [:showcase, :anthropic, :call],
          %{
            duration_ms: duration,
            input_tokens: response.usage.input_tokens,
            output_tokens: response.usage.output_tokens,
            cost_estimate_cents: response.usage.cost_estimate_cents
          },
          %{
            model: model,
            fingerprint: get_in(req.metadata || %{}, [:fingerprint]),
            scenario: get_in(req.metadata || %{}, [:scenario])
          }
        )

        {:ok, response}

      {:error, reason} = err ->
        Logger.error("AnthropicClient.Live call failed: #{inspect(reason)}")

        :telemetry.execute(
          [:showcase, :anthropic, :call_failed],
          %{duration_ms: System.monotonic_time(:millisecond) - start_time},
          %{model: model, reason: reason}
        )

        err
    end
  end

  defp build_body(%Request{} = req, model) do
    [
      model: model,
      messages: req.messages,
      system: req.system,
      max_tokens: req.max_tokens || 4096,
      temperature: req.temperature || 1.0
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp build_response(raw, model) do
    text =
      raw
      |> Map.get("content", [])
      |> Enum.find_value("", fn
        %{"type" => "text", "text" => t} -> t
        _ -> nil
      end)

    usage_in = get_in(raw, ["usage", "input_tokens"]) || 0
    usage_out = get_in(raw, ["usage", "output_tokens"]) || 0

    %Response{
      text: text,
      stop_reason: raw["stop_reason"],
      usage: %Usage{
        input_tokens: usage_in,
        output_tokens: usage_out,
        cost_estimate_cents: cost_cents(model, usage_in, usage_out)
      },
      raw: raw
    }
  end

  defp cost_cents(model, in_tokens, out_tokens) do
    case Map.get(@pricing, model) do
      nil ->
        0.0

      %{input: in_per_m, output: out_per_m} ->
        in_tokens / 1_000_000 * in_per_m + out_tokens / 1_000_000 * out_per_m
    end
  end
end
