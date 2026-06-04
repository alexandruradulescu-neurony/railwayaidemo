defmodule Showcase.OrderFlow.Cascade.ClaudeFallbackStep do
  @moduledoc """
  Last step in the OrderFlow cascade.

  Calls `AnthropicClient` with the raw input + a system prompt that lists
  the catalog summary and asks for a JSON response of shape
  `{"sku": "...", "confidence": 0.0-1.0}`. Parses with `ResilientJSONParser`,
  looks up the product by SKU. Returns `{:match, product, confidence}` or
  `:no_match`.

  Used as the catch-all when exact / fuzzy / client-alias / global-alias all fail.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.OrderFlow.Schemas.Product

  @fingerprint "order_flow:claude_fallback:v1"
  @model "claude-haiku-4-5-20251001"

  @impl true
  def name, do: :claude_fallback

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    req = %Request{
      model: @model,
      messages: [%{role: "user", content: input}],
      system:
        "You are a product matcher. Respond with JSON: {\"sku\": \"...\", \"confidence\": 0.0-1.0}.",
      metadata: %{fingerprint: @fingerprint, scenario: input}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, %{"sku" => sku, "confidence" => confidence}, _completeness} <-
           ResilientJSONParser.parse(response.text),
         %Product{} = product <- repo.one(from p in Product, where: p.sku == ^sku) do
      {:match, product, confidence}
    else
      _ -> :no_match
    end
  end
end
