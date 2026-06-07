defmodule Showcase.OrderFlow.Cascade.ClaudeFallbackStep do
  @moduledoc """
  Last step in the OrderFlow cascade.

  Two execution paths:

    * **Scripted** (seeded scenarios — `MockPrompts.fallback_text_for/1`
      returns a hit): use the canned `{"sku", "confidence"}` text without
      calling AnthropicClient. Keeps seeded demos predictable.
    * **Real** (no scripted match): call `AnthropicClient.call/2` with the
      raw input + a system prompt that includes the **live product catalog**
      so Claude can pick a real SKU instead of inventing one. In dev this
      is real Claude.

  Either way: parses with `ResilientJSONParser`, looks up the product by
  SKU. Returns `{:match, product, confidence}` or `:no_match`.

  ## Why the catalog goes in the system prompt

  Previously the LLM was asked to "match the product" with no context — it
  would invent plausible SKUs that don't exist. With the catalog inlined,
  Claude picks from real SKUs by semantic similarity, which handles long
  descriptive lines like `"AXOR CONTRAACTIONARE GRESITA TOC ALUPLAST"`
  that fuzzy + alias can't catch.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.Product

  @fingerprint "order_flow:claude_fallback:v1"

  @base_system_prompt """
  You are a product-matching assistant for a Romanian feronerie/window
  hardware distributor.

  Given a free-text product description (often abbreviated Romanian:
  "balama", "coltar", "AXOR CREMON OB VARIABIL", etc.) you must pick the
  SINGLE closest product from the catalog below.

  Rules:
    * Respond with JSON ONLY in the shape:
        {"sku": "<exact SKU from catalog>", "confidence": 0.0-1.0}
    * If nothing in the catalog is a reasonable match, respond:
        {"sku": null, "confidence": 0.0}
    * Confidence ≥ 0.85 → strong match (same product, same variant)
      Confidence 0.5-0.84 → reasonable match (family is right, variant
      might differ)
      Confidence < 0.5 → weak — operator should review

  Catalog:
  """

  @doc "The active base system prompt text (without catalog). Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @base_system_prompt

  @impl true
  def name, do: :claude_fallback

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    with {:ok, text} <- response_text(input, repo),
         {:ok, parsed, _completeness} <- ResilientJSONParser.parse(text),
         %{"sku" => sku} when is_binary(sku) <- parsed,
         confidence <- Map.get(parsed, "confidence", 0.5),
         %Product{} = product <- repo.one(from p in Product, where: p.sku == ^sku) do
      {:match, product, normalize_confidence(confidence)}
    else
      _ -> :no_match
    end
  end

  # Prefer scripted text when we recognize the input — seeded scenarios stay
  # predictable. Fall through to AnthropicClient otherwise (real Claude in dev).
  defp response_text(input, repo) do
    case MockPrompts.fallback_text_for(input) do
      {:ok, text} ->
        {:ok, text}

      :not_found ->
        req = %Request{
          model: Config.default_model(),
          messages: [%{role: "user", content: input}],
          system: build_full_prompt(repo),
          metadata: %{fingerprint: @fingerprint, scenario: input}
        }

        case AnthropicClient.call(req) do
          {:ok, response} -> {:ok, response.text}
          {:error, _} = err -> err
        end
    end
  end

  # Build the full system prompt with a freshly-read catalog.
  # ~130 products × ~50 chars ≈ 6.5KB — well within the model's context window.
  defp build_full_prompt(repo) do
    catalog =
      repo.all(from p in Product, select: {p.sku, p.name}, order_by: p.sku)
      |> Enum.map(fn {sku, name} -> "  #{sku}: #{name}" end)
      |> Enum.join("\n")

    @base_system_prompt <> catalog
  end

  defp normalize_confidence(c) when is_number(c), do: c / 1
  defp normalize_confidence(_), do: 0.5
end
