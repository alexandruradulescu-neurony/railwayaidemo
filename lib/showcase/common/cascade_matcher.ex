defmodule Showcase.Common.CascadeMatcher do
  @moduledoc """
  Generic match-cascade engine.

  A demo defines an ordered list of step modules (each implementing
  `CascadeMatcher.Step`). The matcher tries each step in order until one
  returns `{:match, value, confidence}`. If none match, returns
  `%Outcome{matched: false, attempts: [...]}` where `attempts` is the
  per-step trace.

  Used by OrderFlow (product alias cascade) and RecruitFlow (CV cascade).
  Same engine, different step modules.
  """

  defmodule Step do
    @moduledoc """
    Contract for an individual cascade step.

    Steps are pure functions of `(input, context) -> step_result`. They MUST NOT
    read the clock or perform IO directly — context carries everything they need.

    **Context convention** (consumed by Phase 1 OrderFlow + Phase 4 RecruitFlow):

    ```elixir
    %{
      repo: Showcase.Repo,       # required for steps that query the DB
      now: ~U[2026-06-04 12:00:00Z],  # optional — supplied by the boundary if a step
                                      # needs a notion of "now" (e.g., alias decay)
      # demo-specific keys may be added by the caller, e.g.:
      client_id: 42,             # OrderFlow: which client's aliases to consider
      position_id: 7             # RecruitFlow: which position's CVs to match against
    }
    ```

    Steps should pattern-match on the keys they need and ignore the rest. The
    boundary that invokes the cascade is responsible for constructing the context.
    """

    @type input :: term()
    @type context :: map()
    @type confidence :: float()
    @type step_result ::
            {:match, value :: term(), confidence()}
            | :no_match
            | {:error, term()}

    @callback name() :: atom()
    @callback try_match(input(), context()) :: step_result()
  end

  defmodule Attempt do
    @moduledoc false
    defstruct [:step, :result]
    @type t :: %__MODULE__{step: atom(), result: Step.step_result()}
  end

  defmodule Outcome do
    @moduledoc false
    defstruct [:matched, :value, :confidence, :step, :attempts]

    @type t :: %__MODULE__{
            matched: boolean(),
            value: term() | nil,
            confidence: float() | nil,
            step: atom() | nil,
            attempts: list(Attempt.t())
          }
  end

  @doc """
  Run the cascade. Returns an `%Outcome{}` capturing the full attempt trace.
  """
  @spec run(list(module()), Step.input(), Step.context()) :: Outcome.t()
  def run(steps, input, context) when is_list(steps) do
    {result, attempts} =
      Enum.reduce_while(steps, {nil, []}, fn step_mod, {_, attempts} ->
        case step_mod.try_match(input, context) do
          {:match, value, conf} ->
            attempt = %Attempt{step: step_mod.name(), result: {:match, value, conf}}
            {:halt, {{value, conf, step_mod.name()}, [attempt | attempts]}}

          other ->
            attempt = %Attempt{step: step_mod.name(), result: other}
            {:cont, {nil, [attempt | attempts]}}
        end
      end)

    case result do
      {value, conf, step} ->
        %Outcome{
          matched: true,
          value: value,
          confidence: conf,
          step: step,
          attempts: Enum.reverse(attempts)
        }

      nil ->
        %Outcome{matched: false, attempts: Enum.reverse(attempts)}
    end
  end
end
