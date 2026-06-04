defmodule Showcase.Common.AnthropicClient.Mock do
  @moduledoc """
  Test-only implementation of `Showcase.Common.AnthropicClient`.

  Stores registered responses in `:ets`, keyed by `{fingerprint, scenario}`.
  Call `register/2` from test setup; `reset/0` between tests.

  The request must carry `metadata: %{fingerprint: ..., scenario: ...}` to
  match a registration. Scenario defaults to `"default"`.

  ## Async tests

  The ETS table is `:named_table` and globally shared. Tests must call
  `reset/0` in `setup` to avoid leakage across runs in the same file.
  Heavy concurrent usage across multiple `async: true` test files that
  register overlapping `{fingerprint, scenario}` keys could race —
  prefer disjoint keys per test file, or set `async: false` when in doubt.
  """

  @behaviour Showcase.Common.AnthropicClient

  alias Showcase.Common.AnthropicClient.Types.{Request, Response, Usage}

  @table :anthropic_client_mock

  def ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ref -> @table
    end
  end

  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Register a canned response.

  Options:
    * `:scenario` — string, default `"default"`
    * `:text` — required, the response text
    * `:input_tokens` — default 0
    * `:output_tokens` — default 0
    * `:cost_estimate_cents` — default 0.0
    * `:stop_reason` — default `"end_turn"`
  """
  def register(fingerprint, opts) do
    ensure_table()
    scenario = Keyword.get(opts, :scenario, "default")
    text = Keyword.fetch!(opts, :text)

    response = %Response{
      text: text,
      stop_reason: Keyword.get(opts, :stop_reason, "end_turn"),
      usage: %Usage{
        input_tokens: Keyword.get(opts, :input_tokens, 0),
        output_tokens: Keyword.get(opts, :output_tokens, 0),
        cost_estimate_cents: Keyword.get(opts, :cost_estimate_cents, 0.0)
      },
      raw: nil
    }

    :ets.insert(@table, {{fingerprint, scenario}, response})
    :ok
  end

  @impl Showcase.Common.AnthropicClient
  def call(request, opts \\ [])

  def call(%Request{metadata: metadata}, _opts) do
    ensure_table()
    fingerprint = (metadata || %{})[:fingerprint] || (metadata || %{})["fingerprint"]
    scenario = (metadata || %{})[:scenario] || (metadata || %{})["scenario"] || "default"

    case :ets.lookup(@table, {fingerprint, scenario}) do
      [{_, response}] -> {:ok, response}
      [] -> {:error, {:no_mock, fingerprint, scenario}}
    end
  end
end
