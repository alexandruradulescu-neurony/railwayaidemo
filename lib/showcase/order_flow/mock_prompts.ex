defmodule Showcase.OrderFlow.MockPrompts do
  @moduledoc """
  The bundle of (scenario_name, extract_text, fallback_text_or_nil) used by
  both the seed (to plant SyntheticMessages with matching scenarios) and the
  test-time Mock registration.

  Keeping these in one module guarantees the two never drift apart — adding a
  new demo scenario means editing this one file.
  """

  @scenarios [
    %{
      name: "hinges_and_locks",
      kind: "email",
      client_hint: "Acme Inc",
      body: "Hi, I need 200 hinges and 50 door locks for the warehouse — same as last month. Thanks!",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "hinges", "quantity": 200}, {"description": "door locks", "quantity": 50}]}),
      fallback_responses: []
    },
    %{
      name: "gaskets_alias",
      kind: "whatsapp",
      client_hint: "Beta Industries",
      body: "10 boxes of the 4mm gaskets we always order",
      extract_response: ~s({"client_hint": "Beta Industries", "lines": [{"description": "the 4mm gaskets we always order", "quantity": 10}]}),
      # ClaudeFallbackStep won't be called if a client-scoped alias exists (seeded)
      fallback_responses: []
    },
    %{
      name: "mixed_known_unknown",
      kind: "email",
      client_hint: "Acme Inc",
      body: "Send 12 widgets and 3 of those gizmo things",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widgets", "quantity": 12}, {"description": "those gizmo things", "quantity": 3}]}),
      fallback_responses: [
        %{scenario: "those gizmo things", text: ~s({"sku": "GDG-001", "confidence": 0.65})}
      ]
    },
    %{
      name: "low_confidence_mystery",
      kind: "whatsapp",
      client_hint: "Acme Inc",
      body: "some of those things we ordered last time",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "some of those things we ordered last time", "quantity": 1}]}),
      fallback_responses: [
        %{scenario: "some of those things we ordered last time", text: ~s({"sku": "GHOST-999", "confidence": 0.2})}
      ]
    }
  ]

  def scenarios, do: @scenarios
end
