defmodule Showcase.InvoiceApproval.Pipeline do
  @moduledoc """
  Boundary that orchestrates the Invoice Approval pipeline.

  Stages (each broadcasts PubSub on `invoice_approval:processing:<bundle_id>`):
    1. :claude_called      — request sent to AnthropicClient
    2. :claude_returned    — response parsed
    3. :verdict_created    — Verdict row inserted

  Returns `{:ok, %Verdict{}}` on success, `{:error, reason}` otherwise.
  """

  alias Ecto.Multi
  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Impl.Types.Discrepancy
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{DocumentBundle, Verdict}
  alias Showcase.Repo

  @fingerprint "invoice_approval:verdict:v1"
  @system_prompt """
  You compare a contract, one or more delivery notes, and an invoice for a single
  shipment cycle. For every line item across the three documents, report
  discrepancies you detect.

  Respond with JSON ONLY in this exact shape:
    {
      "raw_matrix": [
        {
          "line_key": "<sku or identifier>",
          "contract":  {<contract attrs>}  | null,
          "delivery":  {<delivery attrs>}  | null,
          "invoice":   {<invoice attrs>}   | null,
          "discrepancies": [
            {
              "field": "<unit_price | quantity | due_date | sku_not_in_contract | missing_in_invoice | missing_in_delivery>",
              "contract_value": <value or null>,
              "delivery_value": <value or null>,
              "invoice_value":  <value or null>,
              "diff_value": <numeric difference>,
              "diff_basis": "<pct | absolute | days>"
            }
          ]
        }
      ],
      "summary": "<short prose>"
    }

  No narration outside the JSON.
  """

  @doc "The active system prompt text. Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @spec process_bundle(DocumentBundle.t(), %{now: DateTime.t()}) ::
          {:ok, Verdict.t()} | {:error, term()}
  def process_bundle(%DocumentBundle{} = bundle, %{now: _now}) do
    topic = "invoice_approval:processing:#{bundle.id}"

    broadcast(topic, :claude_called, %{scenario: bundle.scenario})

    with {:ok, response_text} <- response_text(bundle),
         {:ok, parsed, _completeness} <- ResilientJSONParser.parse(response_text),
         _ = broadcast(topic, :claude_returned, %{summary: Map.get(parsed, "summary", "")}),
         raw_matrix <- normalize_matrix(Map.get(parsed, "raw_matrix", [])),
         thresholds <- normalize_thresholds(bundle.thresholds),
         %{outcome: outcome, classified_matrix: classified, reasoning: reasoning} <-
           ThresholdEvaluator.evaluate(raw_matrix, thresholds) do
      multi =
        Multi.new()
        |> Multi.insert(:verdict, Verdict.changeset(%Verdict{}, %{
          bundle_id: bundle.id,
          outcome: Atom.to_string(outcome),
          reasoning: reasoning,
          raw_matrix: %{"rows" => raw_matrix_to_json(raw_matrix)},
          classified_matrix: %{"rows" => classified_matrix_to_json(classified)},
          thresholds_used: bundle.thresholds,
          source: "ai",
          actor: nil
        }))
        # Sync the bundle's status with the verdict so the inbox can show
        # the right badge without re-querying verdicts every render.
        |> Multi.update(:bundle, DocumentBundle.changeset(bundle, %{status: Atom.to_string(outcome)}))

      case Repo.transaction(multi) do
        {:ok, %{verdict: verdict}} ->
          broadcast(topic, :verdict_created, %{verdict_id: verdict.id, outcome: verdict.outcome})
          {:ok, verdict}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    else
      {:error, _} = err -> err
    end
  end

  # ----- helpers -----

  # Branch like OrderFlow: seeded scenarios use scripted JSON (predictable
  # demo, no API costs, no flake). Anything else (e.g. user-uploaded bundles
  # in a future iteration) hits the configured AnthropicClient impl.
  defp response_text(%DocumentBundle{scenario: scenario} = bundle) do
    case MockPrompts.scripted_response_for(scenario) do
      {:ok, text} ->
        {:ok, text}

      :not_found ->
        req = %Request{
          model: Config.default_model(),
          messages: [%{role: "user", content: build_user_message(bundle)}],
          system: @system_prompt,
          metadata: %{fingerprint: @fingerprint, scenario: scenario}
        }

        case AnthropicClient.call(req) do
          {:ok, response} -> {:ok, response.text}
          {:error, _} = err -> err
        end
    end
  end

  defp build_user_message(%DocumentBundle{} = bundle) do
    """
    Contract terms: #{inspect(bundle.contract_id)}
    Delivery notes: #{Jason.encode!(bundle.delivery_notes)}
    Invoice: #{Jason.encode!(bundle.invoice)}
    """
  end

  defp normalize_matrix(rows) when is_list(rows) do
    Enum.map(rows, fn row ->
      %{
        line_key: row["line_key"],
        contract: row["contract"] || %{},
        delivery: row["delivery"] || %{},
        invoice: row["invoice"] || %{},
        discrepancies:
          (row["discrepancies"] || [])
          |> Enum.map(&normalize_discrepancy/1)
          |> Enum.reject(&is_nil/1)
      }
    end)
  end

  defp normalize_matrix(_), do: []

  # Real Claude responses can have null diff_value, missing fields, or
  # unexpected field/basis strings. Tolerate everything — drop the
  # discrepancy entirely if `field` or `diff_basis` aren't usable.
  defp normalize_discrepancy(d) when is_map(d) do
    with field when is_binary(field) <- d["field"],
         basis when is_binary(basis) <- d["diff_basis"] || "absolute" do
      %Discrepancy{
        field: safe_atom(field),
        contract_value: d["contract_value"],
        delivery_value: d["delivery_value"],
        invoice_value: d["invoice_value"],
        diff_value: as_float(d["diff_value"]),
        diff_basis: safe_atom(basis)
      }
    else
      _ -> nil
    end
  end

  defp normalize_discrepancy(_), do: nil

  defp safe_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> String.to_atom(str)
    end
  end

  defp as_float(n) when is_number(n), do: n * 1.0
  defp as_float(_), do: 0.0

  defp normalize_thresholds(thresholds) do
    %{
      price_pct: get(thresholds, "price_pct", 5.0),
      qty_pct: get(thresholds, "qty_pct", 2.0),
      date_days: get(thresholds, "date_days", 3)
    }
  end

  defp get(map, key, default) do
    Map.get(map, key) || Map.get(map, String.to_atom(key)) || default
  end

  defp raw_matrix_to_json(rows) do
    Enum.map(rows, fn row ->
      %{
        "line_key" => row.line_key,
        "contract" => row.contract,
        "delivery" => row.delivery,
        "invoice" => row.invoice,
        "discrepancies" => Enum.map(row.discrepancies, &Map.from_struct/1)
      }
    end)
  end

  defp classified_matrix_to_json(rows) do
    Enum.map(rows, fn row ->
      %{
        "line_key" => row.line_key,
        "contract" => row.contract,
        "delivery" => row.delivery,
        "invoice" => row.invoice,
        "discrepancies" =>
          Enum.map(row.discrepancies, fn cd ->
            %{
              "discrepancy" => Map.from_struct(cd.discrepancy),
              "severity" => Atom.to_string(cd.severity),
              "note" => cd.note
            }
          end)
      }
    end)
  end

  defp broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, topic, {:invoice_approval, event, payload})
  end
end
