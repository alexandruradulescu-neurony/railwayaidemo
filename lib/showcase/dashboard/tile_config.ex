defmodule Showcase.Dashboard.TileConfig do
  @moduledoc """
  Compile-time registry of dashboard tiles. Single source of truth for
  "what demos the showcase ships."

  Adding a new demo: add an entry here, set status to `:live` once the
  demo's LiveView + Seed are wired.
  """

  alias Showcase.Dashboard.Tile

  # Order matches the live-demo flow the AE walks through:
  # OrderFlow → Invoice Approval → Planogram → Restaurant Compliance → RecruitFlow.
  @tiles [
    %Tile{
      id: :order_flow,
      title: "OrderFlow",
      description:
        "Turn unstructured customer messages into structured orders. The system gets smarter every time a human corrects a mismatch.",
      roi_hook: "Replaces hours of manual order re-keying per day with seconds of AI parsing.",
      status: :live,
      path: "/order-flow",
      seeder: Showcase.OrderFlow.Seed
    },
    %Tile{
      id: :invoice_approval,
      title: "Invoice Approval",
      description:
        "Three-way matching across contract, delivery note, and invoice. AI verdicts are explainable; configurable tolerances drive the routing.",
      roi_hook: "AP clerks see only the ambiguous middle; configuration is the dial.",
      status: :live,
      path: "/invoice-approval",
      seeder: Showcase.InvoiceApproval.Seed
    },
    %Tile{
      id: :planogram,
      title: "Planogram Manager",
      description:
        "Retail shelf compliance audits done in seconds via a single vision call returning score, per-row breakdown, and suggested fixes.",
      roi_hook: "Replaces an afternoon of manual audit work with ~3-5¢ per shelf photo.",
      status: :live,
      path: "/planogram",
      seeder: Showcase.Planogram.Seed
    },
    %Tile{
      id: :restaurant_compliance,
      title: "Restaurant Compliance",
      description:
        "Rule-by-rule mise-en-place audits from 4-5 inspector photos. Pass/fail per rule, every violation tied to the photo that proves it.",
      roi_hook: "Replaces an inspector's afternoon with ~5¢ per visit — and surfaces drift before the customer notices.",
      status: :live,
      path: "/restaurant-compliance",
      seeder: Showcase.RestaurantCompliance.Seed
    },
    %Tile{
      id: :recruit_flow,
      title: "RecruitFlow",
      description:
        "Phone-screen, score, and route candidates through a 5-state funnel — AI handles the volume.",
      roi_hook: "Recruiters intervene only on the ambiguous middle — everything else moves automatically.",
      status: :coming_soon,
      path: "/recruit-flow",
      seeder: Showcase.RecruitFlow.Seed
    }
  ]

  @doc "All registered tiles in spec order."
  @spec all() :: list(Tile.t())
  def all, do: @tiles
end
