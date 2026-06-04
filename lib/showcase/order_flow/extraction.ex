defmodule Showcase.OrderFlow.Extraction do
  @moduledoc """
  Boundary that calls `AnthropicClient` to extract `{client_hint, lines}`
  from a raw customer message.

  Expected Claude response shape:
    {"client_hint": "...", "lines": [{"description": "...", "quantity": N}, ...]}

  Returns `{:ok, %{client_hint, lines}}` or `{:error, reason}`.
  """

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.ResilientJSONParser

  @fingerprint "order_flow:extract:v1"
  @model "claude-haiku-4-5-20251001"
  @system_prompt """
  You parse a customer order message into structured data.

  Respond with JSON ONLY in this shape:
    {"client_hint": "<name as customer mentions or implies, or null>",
     "lines": [{"description": "<product name as written>", "quantity": <integer>}, ...]}

  Do not invent. Do not include narration outside the JSON.
  """

  @type extracted_line :: %{description: String.t(), quantity: integer()}
  @type extracted :: %{client_hint: String.t() | nil, lines: list(extracted_line())}

  @spec extract(String.t(), keyword()) :: {:ok, extracted()} | {:error, term()}
  def extract(body, opts \\ []) when is_binary(body) do
    scenario = Keyword.fetch!(opts, :scenario)

    req = %Request{
      model: @model,
      messages: [%{role: "user", content: body}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, raw, _completeness} <- ResilientJSONParser.parse(response.text) do
      parsed = %{
        client_hint: Map.get(raw, "client_hint"),
        lines:
          raw
          |> Map.get("lines", [])
          |> Enum.map(fn line ->
            %{
              description: Map.get(line, "description"),
              quantity: Map.get(line, "quantity")
            }
          end)
          |> Enum.filter(fn line ->
            is_binary(line.description) and is_integer(line.quantity)
          end)
      }

      {:ok, parsed}
    else
      {:error, _} = err -> err
    end
  end
end
