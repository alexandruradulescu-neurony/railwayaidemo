defmodule Showcase.OrderFlow.ExtractionTest do
  # Mock is a process-global GenServer; concurrent test files calling
  # Mock.reset() race with our Mock.register here. Run sync.
  use ExUnit.Case, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Extraction

  setup do
    Mock.reset()
    :ok
  end

  test "extracts client hint + lines from a clean message" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "hinges_and_locks",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "hinges", "quantity": 200}, {"description": "door locks", "quantity": 50}]})
    )

    assert {:ok, result} = Extraction.extract("hi, 200 hinges and 50 door locks", scenario: "hinges_and_locks")
    assert result.client_hint == "Acme Inc"
    assert length(result.lines) == 2
    assert Enum.at(result.lines, 0) == %{description: "hinges", quantity: 200}
  end

  test "returns error when Claude returns malformed json" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "garbage",
      text: "not json"
    )

    assert {:error, _} = Extraction.extract("anything", scenario: "garbage")
  end

  test "returns error when AnthropicClient fails" do
    # Unregistered scenario triggers no_mock
    assert {:error, _} = Extraction.extract("anything", scenario: "unregistered")
  end

  test "salvages a partial JSON response with whatever lines parsed" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "truncated",
      text: ~s({"client_hint": "Acme", "lines": [{"description": "widget", "quantity": 5}, {"description": "gadg)
    )

    {:ok, result} = Extraction.extract("body doesn't matter", scenario: "truncated")
    assert result.client_hint == "Acme"
    assert length(result.lines) == 1
  end
end
