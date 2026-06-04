defmodule Showcase.Common.CascadeMatcherTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.CascadeMatcher
  alias Showcase.Common.CascadeMatcher.{Outcome, Attempt}

  defmodule ExactStep do
    @behaviour CascadeMatcher.Step
    @impl true
    def name, do: :exact
    @impl true
    def try_match(input, context) do
      case Map.get(context.products, input) do
        nil -> :no_match
        product -> {:match, product, 1.0}
      end
    end
  end

  defmodule FuzzyStep do
    @behaviour CascadeMatcher.Step
    @impl true
    def name, do: :fuzzy
    @impl true
    def try_match(input, context) do
      Enum.find_value(context.products, :no_match, fn {key, product} ->
        if String.jaro_distance(input, key) >= 0.75 do
          {:match, product, String.jaro_distance(input, key)}
        else
          nil
        end
      end)
    end
  end

  defmodule FallbackStep do
    @behaviour CascadeMatcher.Step
    @impl true
    def name, do: :fallback
    @impl true
    def try_match(_input, _context), do: {:match, :unknown_product, 0.1}
  end

  defmodule FailStep do
    @behaviour CascadeMatcher.Step
    @impl true
    def name, do: :always_fail
    @impl true
    def try_match(_input, _context), do: :no_match
  end

  setup do
    {:ok, %{products: %{"widget" => :w, "gadget" => :g}}}
  end

  describe "run/3" do
    test "returns the first matching step", ctx do
      outcome = CascadeMatcher.run([ExactStep, FuzzyStep], "widget", ctx)

      assert %Outcome{matched: true, value: :w, confidence: 1.0, step: :exact} = outcome
      assert length(outcome.attempts) == 1
    end

    test "falls through to a later step when earlier ones fail", ctx do
      outcome = CascadeMatcher.run([ExactStep, FuzzyStep], "widgit", ctx)

      assert %Outcome{matched: true, step: :fuzzy} = outcome
      assert outcome.value == :w
      assert outcome.confidence > 0.75
      assert length(outcome.attempts) == 2
      assert %Attempt{step: :exact, result: :no_match} = hd(outcome.attempts)
    end

    test "returns matched: false with full attempt trace if all steps fail", ctx do
      outcome = CascadeMatcher.run([ExactStep, FailStep], "nope", ctx)

      assert %Outcome{matched: false, value: nil, attempts: attempts} = outcome
      assert length(attempts) == 2
    end

    test "fallback step always matches and terminates the cascade", ctx do
      outcome = CascadeMatcher.run([ExactStep, FailStep, FallbackStep], "nope", ctx)

      assert %Outcome{matched: true, value: :unknown_product, step: :fallback} = outcome
      assert length(outcome.attempts) == 3
    end

    test "empty step list returns matched: false with empty attempts" do
      outcome = CascadeMatcher.run([], "anything", %{})

      assert %Outcome{matched: false, attempts: []} = outcome
    end
  end
end
