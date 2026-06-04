defmodule Showcase.OrderFlow.Seed do
  @moduledoc """
  Seeds the OrderFlow demo with synthetic clients, products, a few
  client-scoped aliases, and the curated `SyntheticMessage` bundle from
  `Showcase.OrderFlow.MockPrompts.scenarios/0`.

  Implements `Showcase.Common.DemoSeeder` — invoked by the global Reset.

  Idempotent: every insert uses `on_conflict` so re-running produces identical state.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  @clients [
    %{name: "Acme Inc", email: "orders@acme.example"},
    %{name: "Beta Industries", email: "purchasing@beta.example"},
    %{name: "Gamma Wholesale", email: "ops@gamma.example"}
  ]

  @products [
    %{sku: "WGT-001", name: "Widget", normalized_name: "widgets"},
    %{sku: "GDG-001", name: "Gadget", normalized_name: "gadgets"},
    %{sku: "HNG-001", name: "Hinges", normalized_name: "hinges"},
    %{sku: "LCK-001", name: "Door Locks", normalized_name: "door locks"},
    %{sku: "GSK-4MM", name: "4mm Gasket", normalized_name: "4mm gasket"},
    %{sku: "BLT-M8", name: "M8 Bolts", normalized_name: "m8 bolts"},
    %{sku: "WSH-M8", name: "M8 Washers", normalized_name: "m8 washers"},
    %{sku: "PNT-RED", name: "Red Paint", normalized_name: "red paint"}
  ]

  @impl true
  def name, do: "OrderFlow"

  @impl true
  def tables do
    # children before parents (for TRUNCATE order)
    [
      "of_order_lines",
      "of_orders",
      "of_product_aliases",
      "of_synthetic_messages",
      "of_products",
      "of_clients"
    ]
  end

  @impl true
  def oban_queue, do: :order_flow

  @impl true
  def seed do
    Repo.transaction(fn ->
      seed_clients()
      seed_products()
      seed_aliases()
      seed_messages()
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_clients do
    Enum.each(@clients, fn attrs ->
      %Client{}
      |> Client.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
    end)
  end

  defp seed_products do
    Enum.each(@products, fn attrs ->
      %Product{}
      |> Product.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :sku)
    end)
  end

  defp seed_aliases do
    # One client-scoped alias for Beta Industries: "the 4mm gaskets we always order" → 4mm gasket
    beta = Repo.get_by(Client, name: "Beta Industries")
    gasket = Repo.get_by(Product, sku: "GSK-4MM")

    if beta && gasket do
      existing =
        Repo.get_by(ProductAlias,
          normalized_text: "the 4mm gaskets we always order",
          product_id: gasket.id,
          client_id: beta.id
        )

      unless existing do
        %ProductAlias{}
        |> ProductAlias.changeset(%{
          normalized_text: "the 4mm gaskets we always order",
          product_id: gasket.id,
          client_id: beta.id,
          confidence: 0.85,
          last_used_at: DateTime.add(DateTime.utc_now(), -30, :day),
          use_count: 5,
          source: "seed"
        })
        |> Repo.insert!()
      end
    end
  end

  defp seed_messages do
    Enum.each(MockPrompts.scenarios(), fn s ->
      existing = Repo.get_by(SyntheticMessage, scenario: s.name)

      unless existing do
        %SyntheticMessage{}
        |> SyntheticMessage.changeset(%{
          body: s.body,
          kind: s.kind,
          scenario: s.name,
          client_hint: s.client_hint
        })
        |> Repo.insert!()
      end
    end)
  end
end
