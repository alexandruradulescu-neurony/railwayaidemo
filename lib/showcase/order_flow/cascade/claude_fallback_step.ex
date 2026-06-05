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
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.OrderFlow.Schemas.Product

  @fingerprint "order_flow:claude_fallback:v1"
  @system_prompt "You are a product matcher. Respond with JSON: {\"sku\": \"...\", \"confidence\": 0.0-1.0}."

  @doc "The active system prompt text. Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @impl true
  def name, do: :claude_fallback

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    req = %Request{
      model: Config.default_model(),
      messages: [%{role: "user", content: input}],
      system: @system_prompt,
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
