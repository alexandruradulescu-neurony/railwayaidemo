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
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Impl.Types.Discrepancy
  alias Showcase.InvoiceApproval.Schemas.{DocumentBundle, Verdict}
  alias Showcase.Repo

  @fingerprint "invoice_approval:verdict:v1"
  @model "claude-haiku-4-5-20251001"
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

  @spec process_bundle(DocumentBundle.t(), %{now: DateTime.t()}) ::
          {:ok, Verdict.t()} | {:error, term()}
  def process_bundle(%DocumentBundle{} = bundle, %{now: _now}) do
    topic = "invoice_approval:processing:#{bundle.id}"

    body = build_user_message(bundle)

    req = %Request{
      model: @model,
      messages: [%{role: "user", content: body}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: bundle.scenario}
    }

    broadcast(topic, :claude_called, %{scenario: bundle.scenario})

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, parsed, _completeness} <- ResilientJSONParser.parse(response.text),
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
          |> Enum.map(fn d ->
            %Discrepancy{
              field: String.to_atom(d["field"]),
              contract_value: d["contract_value"],
              delivery_value: d["delivery_value"],
              invoice_value: d["invoice_value"],
              diff_value: d["diff_value"] * 1.0,
              diff_basis: String.to_atom(d["diff_basis"])
            }
          end)
      }
    end)
  end

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
