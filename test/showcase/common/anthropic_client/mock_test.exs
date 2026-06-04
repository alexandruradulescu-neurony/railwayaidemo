defmodule Showcase.Common.AnthropicClient.MockTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.Common.AnthropicClient.Types.{Request, Response, Usage}

  setup do
    Mock.reset()
    :ok
  end

  test "returns the registered response for a matching fingerprint + scenario" do
    Mock.register("greet", scenario: "default", text: "Hello!", input_tokens: 5, output_tokens: 3)

    req = %Request{
      model: "claude-haiku-4-5-20251001",
      messages: [%{role: "user", content: "say hi"}],
      metadata: %{fingerprint: "greet", scenario: "default"}
    }

    assert {:ok, %Response{text: "Hello!", usage: %Usage{input_tokens: 5, output_tokens: 3}}} =
             AnthropicClient.call(req)
  end

  test "different scenarios for the same fingerprint return different responses" do
    Mock.register("eval", scenario: "qualified", text: ~s({"outcome": "qualified"}))
    Mock.register("eval", scenario: "rejected", text: ~s({"outcome": "rejected"}))

    qual = %Request{
      model: "haiku",
      messages: [],
      metadata: %{fingerprint: "eval", scenario: "qualified"}
    }

    rej = %Request{qual | metadata: %{fingerprint: "eval", scenario: "rejected"}}

    assert {:ok, %Response{text: text_q}} = AnthropicClient.call(qual)
    assert {:ok, %Response{text: text_r}} = AnthropicClient.call(rej)
    assert text_q =~ "qualified"
    assert text_r =~ "rejected"
  end

  test "unregistered call returns no_mock error" do
    req = %Request{
      model: "haiku",
      messages: [],
      metadata: %{fingerprint: "unknown", scenario: "default"}
    }

    assert {:error, {:no_mock, "unknown", "default"}} = AnthropicClient.call(req)
  end

  test "cost estimate defaults to zero if not provided" do
    Mock.register("free", text: "no cost data")

    req = %Request{
      model: "haiku",
      messages: [],
      metadata: %{fingerprint: "free", scenario: "default"}
    }

    assert {:ok, %Response{usage: %Usage{cost_estimate_cents: 0.0}}} = AnthropicClient.call(req)
  end
end
