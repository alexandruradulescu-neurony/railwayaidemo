defmodule Showcase.OrderFlow.MockPrompts do
  @moduledoc """
  The bundle of (scenario_name, extract_text, fallback_text_or_nil) used by
  both the seed (to plant SyntheticMessages with matching scenarios) and the
  test-time Mock registration.

  Also exposed to the boundary: seeded messages bypass the AnthropicClient
  impl swap entirely and read scripted text from here, so they stay
  predictable during the live demo regardless of whether `Live` or `Mock` is
  the configured impl. Composed messages (typed by the user in the in-app
  Gmail modal) still go through `AnthropicClient.call/2` and hit real Claude
  in dev/prod.

  Keeping these in one module guarantees the seed loop and the Mock
  registration never drift apart — adding a new demo scenario means editing
  this one file.
  """

  @scenarios [
    # ── Meesenburg demo scenarios (seeded into the live demo inbox) ───────
    %{
      name: "meesenburg_clean_sku",
      kind: "email",
      client_hint: "Alexandru Erdei",
      from_address: "alexandru.erdei@meesenburg.ro",
      subject: "Comandă mânere + colțare",
      body:
        "Bună ziua,\n\nVă rog să trimiteți: 10 buc K1001-07-n03, 5 buc K1001-11-n03, 20 buc colțar jos, 20 buc colțar sus.\n\nMulțumesc,\nAlex",
      extract_response: ~s({"client_hint": "Alexandru Erdei", "lines": [{"description": "K1001-07-n03", "quantity": 10}, {"description": "K1001-11-n03", "quantity": 5}, {"description": "coltar jos", "quantity": 20}, {"description": "coltar sus", "quantity": 20}]}),
      fallback_responses: []
    },
    %{
      name: "meesenburg_informal",
      kind: "email",
      client_hint: "Dragos Manolache",
      from_address: "dragosimcom@gmail.com",
      subject: "Cerere balamale + mecanisme",
      body:
        "Bună ziua,\n\nAm nevoie de 10 balama, 5 mecanisme OB pentru ferestre 2400, și 30 brațe dreapta 600/800.\n\nMulțumesc!\nDragos",
      extract_response: ~s({"client_hint": "Dragos Manolache", "lines": [{"description": "balama", "quantity": 10}, {"description": "mecanism ob", "quantity": 5}, {"description": "brat dreapta", "quantity": 30}]}),
      fallback_responses: []
    },
    %{
      name: "meesenburg_mixed",
      kind: "email",
      client_hint: "Meesenburg Romania",
      from_address: "alexandru.erdei@meesenburg.ro",
      subject: "Comandă mixtă feronerie",
      body:
        "Bună ziua,\n\nVă rog: K2001-06-n03 = 10 buc, broască multipunct = 5 buc, 50 buc semibalamale inferioare TOC, BIT-PH2-BOX = 1 cutie.\n\nMulțumesc,\nAlex (Meesenburg)",
      extract_response: ~s({"client_hint": "Meesenburg Romania", "lines": [{"description": "K2001-06-n03", "quantity": 10}, {"description": "broasca multipunct", "quantity": 5}, {"description": "semibalama", "quantity": 50}, {"description": "BIT-PH2-BOX", "quantity": 1}]}),
      fallback_responses: []
    }
  ]

  def scenarios, do: @scenarios

  @doc """
  Scenarios planted into the demo inbox as `SyntheticMessage` rows. All
  three Meesenburg scenarios qualify; the older Acme/Beta/Gamma scenarios
  were deleted along with their legacy clients (REVIEW.md HI-03 + MED-06).
  """
  def seed_scenarios, do: @scenarios

  @doc """
  Look up the scripted extract response text for a scenario name.

  Returns `{:ok, text}` or `:not_found`. Used by the boundary to bypass
  AnthropicClient for seeded (`composed: false`) messages.
  """
  @spec extract_text_for(String.t() | nil) :: {:ok, String.t()} | :not_found
  def extract_text_for(nil), do: :not_found

  def extract_text_for(name) when is_binary(name) do
    case Enum.find(@scenarios, &(&1.name == name)) do
      nil -> :not_found
      s -> {:ok, s.extract_response}
    end
  end

  @doc """
  Look up the scripted Claude-fallback text for a description (the step
  passes the raw description as the "scenario" hint).

  Returns `{:ok, text}` or `:not_found`.
  """
  @spec fallback_text_for(String.t() | nil) :: {:ok, String.t()} | :not_found
  def fallback_text_for(nil), do: :not_found

  def fallback_text_for(description) when is_binary(description) do
    @scenarios
    |> Enum.flat_map(& &1.fallback_responses)
    |> Enum.find(&(&1.scenario == description))
    |> case do
      nil -> :not_found
      %{text: text} -> {:ok, text}
    end
  end
end
