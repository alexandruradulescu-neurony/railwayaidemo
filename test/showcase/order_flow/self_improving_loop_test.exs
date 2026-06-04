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

    msg = Repo.get_by!(SyntheticMessage, scenario: "mixed_known_unknown")
    {:ok, %{message: msg}}
  end

  test "after a correction, re-running the same message uses the new alias instead of LLM fallback",
       %{message: msg} do
    # First run — "those gizmo things" gets matched via Claude fallback (per Mock registration).
    {:ok, order1} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    gizmo_line =
      Repo.preload(order1, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "gizmo"))

    assert gizmo_line.match_step == "claude_fallback"

    # Correct it: link to Gadget product manually, simulating the operator UI action.
    gadget = Repo.get_by!(Product, sku: "GDG-001")
    client = Repo.get_by!(Client, name: "Acme Inc")
    now = DateTime.utc_now()

    %ProductAlias{}
    |> ProductAlias.changeset(%{
      normalized_text: Showcase.OrderFlow.Impl.Normalize.normalize_text(gizmo_line.raw_description),
      product_id: gadget.id,
      client_id: client.id,
      confidence: 0.9,
      last_used_at: now,
      use_count: 1,
      source: "correction"
    })
    |> Repo.insert!()

    # Drop the order — pretend the operator ran the same message again.
    Repo.delete!(order1)

    # Re-run the same message — this time the client_alias step should hit, no LLM call.
    {:ok, order2} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    gizmo_line2 =
      Repo.preload(order2, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "gizmo"))

    assert gizmo_line2.match_step == "client_alias"
    assert gizmo_line2.product_id == gadget.id
  end
end
