defmodule Showcase.Common.SystemPromptTest do
  use Showcase.DataCase, async: true

  alias Showcase.Common.SystemPrompt

  test "create + latest round-trip" do
    {:ok, _} =
      SystemPrompt
      |> Ash.Changeset.for_create(:create, %{
        demo: "order_flow",
        section: "extraction",
        version: 1,
        body: "You are an order extractor."
      })
      |> Ash.create()

    {:ok, _} =
      SystemPrompt
      |> Ash.Changeset.for_create(:create, %{
        demo: "order_flow",
        section: "extraction",
        version: 2,
        body: "You are an order extractor v2."
      })
      |> Ash.create()

    {:ok, [%{version: 2, body: body}]} = SystemPrompt.latest("order_flow", "extraction")
    assert body == "You are an order extractor v2."
  end
end
