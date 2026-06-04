defmodule Showcase.OrderFlow.Cascade.ClaudeFallbackStepTest do
  use Showcase.DataCase, async: true

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Cascade.ClaudeFallbackStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, %{widget: widget}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "returns match when Claude responds with a known SKU", %{widget: widget} do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "the gizmo thing",
      text: ~s({"sku": "WGT-001", "confidence": 0.72})
    )

    {:match, found, score} = ClaudeFallbackStep.try_match("the gizmo thing", ctx())
    assert found.id == widget.id
    assert score == 0.72
  end

  test "no_match when Claude returns a SKU not in the DB" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "unknown thing",
      text: ~s({"sku": "GHOST-999", "confidence": 0.9})
    )

    assert ClaudeFallbackStep.try_match("unknown thing", ctx()) == :no_match
  end

  test "no_match when Claude returns malformed JSON" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "bad json",
      text: "not json at all"
    )

    assert ClaudeFallbackStep.try_match("bad json", ctx()) == :no_match
  end

  test "salvages a truncated JSON response with :partial flag" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "truncated",
      text: ~s({"sku": "WGT-001", "confidence": 0.5)
    )

    # ResilientJSONParser should salvage; we still match the product.
    {:match, _found, score} = ClaudeFallbackStep.try_match("truncated", ctx())
    assert score == 0.5
  end

  test "no_match when AnthropicClient returns an error" do
    # No Mock.register — unregistered call returns {:error, {:no_mock, _, _}}
    assert ClaudeFallbackStep.try_match("no mock registered", ctx()) == :no_match
  end

  test "name/0 returns :claude_fallback" do
    assert ClaudeFallbackStep.name() == :claude_fallback
  end
end
