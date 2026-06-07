defmodule Showcase.OrderFlow.SelfImprovingLoopTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  setup do
    Mock.reset()
    OrderFlow.register_mock_responses()
    OrderFlow.Seed.seed()

    # Register a scenario whose extraction returns one matchable line (an
    # exact SKU) and one unknown phrase ("the brown handles") that falls
    # through to Claude fallback. After the operator corrects the unknown,
    # a re-run should pick up the new alias instead of calling Claude.
    Mock.register(
      "order_flow:extract:v1",
      scenario: "self_improving_loop_test",
      text:
        ~s({"client_hint": "Meesenburg Romania", "lines": [{"description": "K1001-11-n03", "quantity": 5}, {"description": "the brown handles", "quantity": 3}]})
    )

    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "the brown handles",
      text: ~s({"sku": "K1001-11-n03", "confidence": 0.55})
    )

    {:ok, msg} =
      %SyntheticMessage{}
      |> SyntheticMessage.changeset(%{
        body: "5x K1001-11-n03 plus 3 of the brown handles",
        kind: "email",
        scenario: "self_improving_loop_test",
        client_hint: "Meesenburg Romania",
        composed: false
      })
      |> Repo.insert()

    {:ok, %{message: msg}}
  end

  test "after a correction, re-running the same message uses the new alias instead of LLM fallback",
       %{message: msg} do
    # First run — "the brown handles" hits claude_fallback (low confidence
    # → still matched, but flagged as such).
    {:ok, order1} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    fuzzy_line =
      Repo.preload(order1, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "brown"))

    assert fuzzy_line.match_step == "claude_fallback"

    # Operator correction — link to the Mâner ușă AXOR maro product.
    product = Repo.get_by!(Product, sku: "K1001-11-n03")
    client = Repo.get_by!(Client, name: "Meesenburg Romania")
    now = DateTime.utc_now()

    %ProductAlias{}
    |> ProductAlias.changeset(%{
      normalized_text: Showcase.OrderFlow.Impl.Normalize.normalize_text(fuzzy_line.raw_description),
      product_id: product.id,
      client_id: client.id,
      confidence: 0.9,
      last_used_at: now,
      use_count: 1,
      source: "correction"
    })
    |> Repo.insert!()

    Repo.delete!(order1)

    # Re-run the same message — the client_alias step should hit now.
    {:ok, order2} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    fuzzy_line2 =
      Repo.preload(order2, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "brown"))

    assert fuzzy_line2.match_step == "client_alias"
    assert fuzzy_line2.product_id == product.id
  end
end
