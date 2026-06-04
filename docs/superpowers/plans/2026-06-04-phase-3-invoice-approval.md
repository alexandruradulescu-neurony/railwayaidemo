# Phase 3: Invoice Approval Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Invoice Approval demo end-to-end. AE picks a client + a curated scenario (e.g., "qty mismatch", "price drift", "missing delivery note"); the pipeline calls Claude once with contract + delivery notes + invoice to produce a raw matching matrix; a pure `ThresholdEvaluator` classifies each discrepancy as green/amber/red based on configurable thresholds and routes the outcome to `approve | reject | needs_human`. The audience sees the 3-column matching view live; moving threshold sliders re-classifies the matrix without another Claude call. AE can override the AI verdict; the override writes an `AuditLog` entry.

**Architecture:** Plain Ecto schemas under `ia_*` prefix (Client, Contract, DocumentBundle, Verdict). Multi-document Claude call via `Showcase.Common.AnthropicClient` returns a raw discrepancy matrix; response parsed by `Showcase.Common.ResilientJSONParser`. A pure `Showcase.InvoiceApproval.Impl.ThresholdEvaluator` separates LLM extraction from business rules — slider changes re-evaluate without re-calling Claude. `Pipeline` boundary owns `Ecto.Multi` + PubSub broadcasts on `invoice_approval:processing:<bundle_id>`. Oban worker on `:invoice_approval` queue. Two LiveViews: `QueueLive` (bundle picker) at `/invoice-approval`, `BundleDetailLive` at `/invoice-approval/bundles/:id` with the 3-column matrix, threshold sliders, verdict display, and override action.

**Tech Stack:**
- Builds on `main` after Phase 2 merge (tag `phase-2` at HEAD-equivalent commit; `main` head currently `d5c7516`).
- Plain Ecto schemas, JSONB columns for nested document content (no per-line-item tables — keeps the demo simple).
- `Showcase.Common.AnthropicClient` (Mock in tests, Live elsewhere) with new fingerprint `invoice_approval:verdict:v1`.
- `Showcase.Common.ResilientJSONParser` parses the multi-document response.
- `Showcase.Common.NeedsHuman.Decision` shape returned alongside the verdict.
- `Showcase.Common.AuditLog` records overrides.
- Oban `:invoice_approval` queue (configured in Phase 0 T3).
- LiveView + Phoenix.PubSub for the queue → detail-view progress signal.

**Reference spec:** `docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md` §4.4

---

## File structure produced by this phase

```
lib/
  showcase/
    invoice_approval.ex                          # public context: list_bundles, find_bundle,
                                                 #                 latest_verdict, register_mock_responses,
                                                 #                 enqueue
    invoice_approval/
      schemas/
        client.ex                                # ia_clients (id, name, contact)
        contract.ex                              # ia_contracts (id, client_id, name, body jsonb,
                                                 #               default_thresholds jsonb,
                                                 #               valid_from, valid_until)
        document_bundle.ex                       # ia_document_bundles (id, client_id, contract_id,
                                                 #                       scenario, kind,
                                                 #                       delivery_notes jsonb,
                                                 #                       invoice jsonb,
                                                 #                       thresholds jsonb)
        verdict.ex                               # ia_verdicts (id, bundle_id, outcome, reasoning,
                                                 #              raw_matrix jsonb, classified_matrix jsonb,
                                                 #              thresholds_used jsonb, source,
                                                 #              actor, inserted_at)
      impl/
        types.ex                                 # %Discrepancy{}, %ClassifiedDiscrepancy{},
                                                 #  %MatchingMatrix{}, helpers
        threshold_evaluator.ex                   # pure: classify/2, evaluate/3, outcome_from/1
      pipeline.ex                                # boundary: process_bundle/2
      worker.ex                                  # Oban worker on :invoice_approval queue
      seed.ex                                    # @behaviour DemoSeeder + description/0 + oban_queue/0
      mock_prompts.ex                            # scenario bundle + canned Mock responses

  showcase_web/
    live/
      invoice_approval/
        queue_live.ex                            # the /invoice-approval page (list of bundles)
        bundle_detail_live.ex                    # /invoice-approval/bundles/:id (matrix + sliders + verdict)
        components/
          matching_matrix.ex                     # 3-column matrix function component
          threshold_sliders.ex                   # 3 sliders with phx-change re-evaluation
          verdict_panel.ex                       # outcome badge + reasoning text

  showcase/dashboard/
    tile_config.ex                               # MODIFY: flip invoice_approval to :live + path + seeder

priv/repo/migrations/
  <ts>_create_invoice_approval_schemas.exs       # all ia_* tables in one migration

test/
  showcase/invoice_approval/
    impl/
      types_test.exs                             # struct shape tests (small)
      threshold_evaluator_test.exs               # heavy TDD: classify, evaluate, outcome_from
    pipeline_test.exs                            # integration: bundle → Claude → matrix → verdict
    worker_test.exs                              # Oban worker contract
    seed_test.exs                                # DemoSeeder behaviour + idempotency
  showcase_web/live/invoice_approval/
    queue_live_test.exs
    bundle_detail_live_test.exs                  # 3-column render + slider re-eval + override
```

**Boundary rules** (per CLAUDE.md, reinforced in earlier phases):
- Pure functions in `impl/` — no Repo, no HTTP, no clock reads. Boundary supplies `now`/`repo` via args.
- `Pipeline` owns `Ecto.Multi`, `AnthropicClient.call/2`, transaction boundaries, PubSub broadcasts.
- `MockPrompts` is consumed by both `register_mock_responses/0` (test/dev) and `Seed.seed/0` (so seeded scenarios always have a matching Mock entry).
- Cross-demo joins forbidden: `ia_clients` is its own table, **not** a foreign key into `of_clients`.

---

## Task 1: Schemas + migration

**Files:**
- Create: `lib/showcase/invoice_approval/schemas/client.ex`
- Create: `lib/showcase/invoice_approval/schemas/contract.ex`
- Create: `lib/showcase/invoice_approval/schemas/document_bundle.ex`
- Create: `lib/showcase/invoice_approval/schemas/verdict.ex`
- Create: `priv/repo/migrations/<ts>_create_invoice_approval_schemas.exs`

### Step 1: Generate migration

```bash
mix ecto.gen.migration create_invoice_approval_schemas
```

Note the timestamp.

### Step 2: Write the migration body

Replace the generated file's contents with:

```elixir
defmodule Showcase.Repo.Migrations.CreateInvoiceApprovalSchemas do
  use Ecto.Migration

  def change do
    create table(:ia_clients) do
      add :name, :string, null: false
      add :contact, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ia_clients, [:name])

    create table(:ia_contracts) do
      add :client_id, references(:ia_clients, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :body, :map, null: false, default: %{}             # line_items list, terms, etc.
      add :default_thresholds, :map, null: false, default: %{}
      add :valid_from, :date
      add :valid_until, :date
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ia_contracts, [:client_id])

    create table(:ia_document_bundles) do
      add :client_id, references(:ia_clients, on_delete: :nilify_all)
      add :contract_id, references(:ia_contracts, on_delete: :nilify_all)
      add :scenario, :string, null: false                    # matches Mock fingerprint+scenario
      add :kind, :string, null: false                        # "clean" | "qty_mismatch" | etc.
      add :delivery_notes, :map, null: false, default: %{}   # array under "items" key
      add :invoice, :map, null: false, default: %{}
      add :thresholds, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ia_document_bundles, [:client_id])
    create index(:ia_document_bundles, [:scenario])

    create table(:ia_verdicts) do
      add :bundle_id, references(:ia_document_bundles, on_delete: :delete_all), null: false
      add :outcome, :string, null: false                     # "approve" | "reject" | "needs_human"
      add :reasoning, :text, null: false
      add :raw_matrix, :map, null: false, default: %{}       # Claude's output before threshold classification
      add :classified_matrix, :map, null: false, default: %{}# after ThresholdEvaluator
      add :thresholds_used, :map, null: false, default: %{}
      add :source, :string, null: false                      # "ai" | "override"
      add :actor, :string                                    # null for "ai", user/email for "override"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ia_verdicts, [:bundle_id, :inserted_at])
  end
end
```

### Step 3: Create the schema modules

Create `lib/showcase/invoice_approval/schemas/client.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Schemas.Client do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ia_clients" do
    field :name, :string
    field :contact, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :contact])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
```

Create `lib/showcase/invoice_approval/schemas/contract.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Schemas.Contract do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.{Client, DocumentBundle}

  schema "ia_contracts" do
    field :name, :string
    field :body, :map, default: %{}
    field :default_thresholds, :map, default: %{}
    field :valid_from, :date
    field :valid_until, :date

    belongs_to :client, Client, foreign_key: :client_id
    has_many :document_bundles, DocumentBundle, foreign_key: :contract_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(contract, attrs) do
    contract
    |> cast(attrs, [:client_id, :name, :body, :default_thresholds, :valid_from, :valid_until])
    |> validate_required([:client_id, :name])
  end
end
```

Create `lib/showcase/invoice_approval/schemas/document_bundle.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Schemas.DocumentBundle do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, Verdict}

  schema "ia_document_bundles" do
    field :scenario, :string
    field :kind, :string
    field :delivery_notes, :map, default: %{}
    field :invoice, :map, default: %{}
    field :thresholds, :map, default: %{}

    belongs_to :client, Client, foreign_key: :client_id
    belongs_to :contract, Contract, foreign_key: :contract_id
    has_many :verdicts, Verdict, foreign_key: :bundle_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [:client_id, :contract_id, :scenario, :kind, :delivery_notes, :invoice, :thresholds])
    |> validate_required([:scenario, :kind])
  end
end
```

Create `lib/showcase/invoice_approval/schemas/verdict.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Schemas.Verdict do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.InvoiceApproval.Schemas.DocumentBundle

  schema "ia_verdicts" do
    field :outcome, :string
    field :reasoning, :string
    field :raw_matrix, :map, default: %{}
    field :classified_matrix, :map, default: %{}
    field :thresholds_used, :map, default: %{}
    field :source, :string
    field :actor, :string

    belongs_to :bundle, DocumentBundle, foreign_key: :bundle_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @valid_outcomes ["approve", "reject", "needs_human"]
  @valid_sources ["ai", "override"]

  def changeset(verdict, attrs) do
    verdict
    |> cast(attrs, [:bundle_id, :outcome, :reasoning, :raw_matrix, :classified_matrix,
                    :thresholds_used, :source, :actor])
    |> validate_required([:bundle_id, :outcome, :reasoning, :source])
    |> validate_inclusion(:outcome, @valid_outcomes)
    |> validate_inclusion(:source, @valid_sources)
  end
end
```

### Step 4: Run migration + verify

```bash
mix ecto.migrate
mix compile --warnings-as-errors
```

Verify the tables exist:

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d showcase_dev -c "\d ia_verdicts" 2>&1 | head -25
```

Expected: shows `ia_verdicts` columns including `raw_matrix`, `classified_matrix`, `outcome`, `source`.

### Step 5: Verify tests unchanged

```bash
mix test 2>&1 | tail -3
```

Expected: 1 property + ~132 tests, 0 failures.

### Step 6: Commit

```bash
git add lib/showcase/invoice_approval/schemas/ priv/repo/migrations/
git commit -m "feat(invoice_approval): schemas + migration for ia_* tables"
```

## Context

- Phase 3, Task 1. Branch: `phase-3-invoice-approval`. Starts off `main` at `d5c7516`.
- Working directory: `/Users/alex/Code/proj-aidemo`.
- `ia_*` prefix follows the spec table-naming convention; cross-demo joins remain forbidden.
- Nested document content (delivery_notes, invoice) goes in JSONB columns to keep the demo simple — no per-line-item tables.

## Report

- Status, files created, migration filename, test count, commit SHA.

---

## Task 2: Types module — `%Discrepancy{}`, `%ClassifiedDiscrepancy{}`, `%MatchingMatrixRow{}`

**Files:**
- Create: `lib/showcase/invoice_approval/impl/types.ex`
- Create: `test/showcase/invoice_approval/impl/types_test.exs`

The structs that flow between Claude (raw matrix), ThresholdEvaluator (classified matrix), and the LiveView (display). Kept in one module for cohesion.

### Step 1: Write failing tests

Create `test/showcase/invoice_approval/impl/types_test.exs`:

```elixir
defmodule Showcase.InvoiceApproval.Impl.TypesTest do
  use ExUnit.Case, async: true

  alias Showcase.InvoiceApproval.Impl.Types
  alias Showcase.InvoiceApproval.Impl.Types.{Discrepancy, ClassifiedDiscrepancy, MatchingMatrixRow}

  test "Discrepancy struct enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(Discrepancy, %{})
    end
  end

  test "Discrepancy with required keys constructs cleanly" do
    d = %Discrepancy{
      field: :unit_price,
      contract_value: 10.0,
      delivery_value: 10.0,
      invoice_value: 10.5,
      diff_value: 5.0,
      diff_basis: :pct
    }

    assert d.field == :unit_price
    assert d.diff_basis == :pct
  end

  test "ClassifiedDiscrepancy wraps a Discrepancy with severity + note" do
    d = %Discrepancy{
      field: :quantity,
      contract_value: 100,
      delivery_value: 100,
      invoice_value: 95,
      diff_value: 5.0,
      diff_basis: :pct
    }

    classified = %ClassifiedDiscrepancy{discrepancy: d, severity: :amber, note: "5% qty drift"}

    assert classified.severity == :amber
    assert classified.discrepancy.field == :quantity
  end

  test "MatchingMatrixRow holds line_key + per-doc cells + classified discrepancies" do
    row = %MatchingMatrixRow{
      line_key: "WGT-001",
      contract: %{qty: 100, unit_price: 10.0},
      delivery: %{qty: 100, unit_price: 10.0},
      invoice: %{qty: 100, unit_price: 10.5},
      discrepancies: []
    }

    assert row.line_key == "WGT-001"
    assert row.contract.qty == 100
  end

  test "row_severity/1 returns :green when no discrepancies" do
    assert Types.row_severity(%MatchingMatrixRow{
             line_key: "x",
             contract: %{},
             delivery: %{},
             invoice: %{},
             discrepancies: []
           }) == :green
  end

  test "row_severity/1 returns the worst severity across discrepancies" do
    row = %MatchingMatrixRow{
      line_key: "x",
      contract: %{},
      delivery: %{},
      invoice: %{},
      discrepancies: [
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :a, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :green, note: ""},
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :b, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :amber, note: ""},
        %ClassifiedDiscrepancy{discrepancy: %Discrepancy{field: :c, contract_value: 1, delivery_value: 1, invoice_value: 1, diff_value: 0.0, diff_basis: :pct}, severity: :red, note: ""}
      ]
    }

    assert Types.row_severity(row) == :red
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/invoice_approval/impl/types_test.exs
```

### Step 3: Implement Types

Create `lib/showcase/invoice_approval/impl/types.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Impl.Types do
  @moduledoc """
  Structs that flow through the Invoice Approval pipeline:

    * `Discrepancy` — raw output from Claude, before threshold classification.
    * `ClassifiedDiscrepancy` — same data + a `:severity` (`:green | :amber | :red`)
      assigned by `ThresholdEvaluator`.
    * `MatchingMatrixRow` — one row across all three documents, with the line's
      classified discrepancies.

  Plus a `row_severity/1` helper that returns the worst severity of any
  classified discrepancy on a row (or `:green` if there are none).
  """

  defmodule Discrepancy do
    @enforce_keys [:field, :contract_value, :delivery_value, :invoice_value, :diff_value, :diff_basis]
    defstruct [:field, :contract_value, :delivery_value, :invoice_value, :diff_value, :diff_basis]

    @type t :: %__MODULE__{
            field: atom(),
            contract_value: any(),
            delivery_value: any(),
            invoice_value: any(),
            diff_value: float(),
            diff_basis: :pct | :absolute | :days
          }
  end

  defmodule ClassifiedDiscrepancy do
    @enforce_keys [:discrepancy, :severity, :note]
    defstruct [:discrepancy, :severity, :note]

    @type severity :: :green | :amber | :red
    @type t :: %__MODULE__{discrepancy: Discrepancy.t(), severity: severity(), note: String.t()}
  end

  defmodule MatchingMatrixRow do
    @enforce_keys [:line_key, :contract, :delivery, :invoice, :discrepancies]
    defstruct [:line_key, :contract, :delivery, :invoice, :discrepancies]

    @type t :: %__MODULE__{
            line_key: String.t(),
            contract: map(),
            delivery: map(),
            invoice: map(),
            discrepancies: list(ClassifiedDiscrepancy.t())
          }
  end

  @doc """
  Returns the worst severity across the row's classified discrepancies.
  `:green` when there are no discrepancies.
  """
  @spec row_severity(MatchingMatrixRow.t()) :: ClassifiedDiscrepancy.severity()
  def row_severity(%MatchingMatrixRow{discrepancies: []}), do: :green

  def row_severity(%MatchingMatrixRow{discrepancies: discs}) do
    severities = Enum.map(discs, & &1.severity)

    cond do
      :red in severities -> :red
      :amber in severities -> :amber
      true -> :green
    end
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/invoice_approval/impl/types_test.exs
```

Expected: 6 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/invoice_approval/impl/types.ex test/showcase/invoice_approval/impl/types_test.exs
git commit -m "feat(invoice_approval): Discrepancy / ClassifiedDiscrepancy / MatchingMatrixRow types"
```

## Context

- Phase 3, Task 2. Branch: `phase-3-invoice-approval`. HEAD after T1.
- Pure structs + one tiny helper. No Repo, no IO.

## Report

- Status, test count, commit SHA. Brief.

---

## Task 3: `ThresholdEvaluator` pure module (heavy TDD)

**Files:**
- Create: `lib/showcase/invoice_approval/impl/threshold_evaluator.ex`
- Create: `test/showcase/invoice_approval/impl/threshold_evaluator_test.exs`

**Contract:** Given a `raw_matrix` (list of `MatchingMatrixRow`-shaped data with raw `Discrepancy` structs) and a `thresholds` map (`%{price_pct, qty_pct, date_days}`), returns:

- `%{outcome: :approve | :reject | :needs_human, classified_matrix: [...rows with ClassifiedDiscrepancy...], reasoning: String.t()}`.

**Classification rules (per discrepancy):**
- `:green` if `diff_value` ≤ threshold for that field's basis.
- `:amber` if threshold < `diff_value` ≤ 2× threshold.
- `:red` if `diff_value` > 2× threshold.

**Outcome rules (across whole matrix):**
- Any row with `:red` → `:reject`.
- No `:red`, at least one `:amber` → `:needs_human`.
- All rows `:green` → `:approve`.

Threshold field → discrepancy field mapping:
- `price_pct` → discrepancies where `field` is `:unit_price` or `:total_price` (basis: `:pct`)
- `qty_pct` → discrepancies where `field` is `:quantity` (basis: `:pct`)
- `date_days` → discrepancies where `field` is `:date`, `:due_date`, `:delivery_date` (basis: `:days`)
- Anything else (e.g., `:sku_not_in_contract`, `:missing_in_invoice`) → always `:red`

### Step 1: Write failing tests

Create `test/showcase/invoice_approval/impl/threshold_evaluator_test.exs`:

```elixir
defmodule Showcase.InvoiceApproval.Impl.ThresholdEvaluatorTest do
  use ExUnit.Case, async: true

  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Impl.Types.Discrepancy

  @thresholds %{price_pct: 5.0, qty_pct: 2.0, date_days: 3}

  defp row(line_key, discs) do
    %{
      line_key: line_key,
      contract: %{},
      delivery: %{},
      invoice: %{},
      discrepancies: discs
    }
  end

  defp d(field, diff, basis) do
    %Discrepancy{
      field: field,
      contract_value: 0,
      delivery_value: 0,
      invoice_value: 0,
      diff_value: diff,
      diff_basis: basis
    }
  end

  describe "classify_severity/2" do
    test "price discrepancy within threshold → :green" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 3.0, :pct), @thresholds) == :green
    end

    test "price discrepancy at threshold → :green" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 5.0, :pct), @thresholds) == :green
    end

    test "price discrepancy between threshold and 2x → :amber" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 7.5, :pct), @thresholds) == :amber
    end

    test "price discrepancy at 2x threshold → :amber" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 10.0, :pct), @thresholds) == :amber
    end

    test "price discrepancy beyond 2x → :red" do
      assert ThresholdEvaluator.classify_severity(d(:unit_price, 15.0, :pct), @thresholds) == :red
    end

    test "qty discrepancy uses qty_pct threshold" do
      assert ThresholdEvaluator.classify_severity(d(:quantity, 1.0, :pct), @thresholds) == :green
      assert ThresholdEvaluator.classify_severity(d(:quantity, 3.0, :pct), @thresholds) == :amber
      assert ThresholdEvaluator.classify_severity(d(:quantity, 8.0, :pct), @thresholds) == :red
    end

    test "date discrepancy uses date_days threshold" do
      assert ThresholdEvaluator.classify_severity(d(:due_date, 2.0, :days), @thresholds) == :green
      assert ThresholdEvaluator.classify_severity(d(:due_date, 5.0, :days), @thresholds) == :amber
      assert ThresholdEvaluator.classify_severity(d(:due_date, 10.0, :days), @thresholds) == :red
    end

    test "out-of-contract discrepancy → :red regardless of threshold" do
      assert ThresholdEvaluator.classify_severity(d(:sku_not_in_contract, 0.0, :absolute), @thresholds) == :red
    end

    test "missing-in-invoice discrepancy → :red" do
      assert ThresholdEvaluator.classify_severity(d(:missing_in_invoice, 0.0, :absolute), @thresholds) == :red
    end
  end

  describe "evaluate/2" do
    test "all-green matrix → :approve" do
      raw_matrix = [
        row("A", [d(:unit_price, 1.0, :pct)]),
        row("B", [d(:quantity, 0.5, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :approve
      assert is_binary(result.reasoning)

      assert Enum.all?(result.classified_matrix, fn row ->
        Enum.all?(row.discrepancies, &(&1.severity == :green))
      end)
    end

    test "any-red matrix → :reject with reasoning citing the worst" do
      raw_matrix = [
        row("A", [d(:unit_price, 20.0, :pct)]),
        row("B", [d(:quantity, 0.5, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :reject
      assert result.reasoning =~ "A"
      assert result.reasoning =~ "unit_price"
    end

    test "amber-only matrix → :needs_human" do
      raw_matrix = [
        row("A", [d(:unit_price, 7.5, :pct)]),
        row("B", [d(:quantity, 3.0, :pct)])
      ]

      result = ThresholdEvaluator.evaluate(raw_matrix, @thresholds)

      assert result.outcome == :needs_human
    end

    test "empty matrix → :approve" do
      assert ThresholdEvaluator.evaluate([], @thresholds).outcome == :approve
    end

    test "row with no discrepancies → contributes :green" do
      raw_matrix = [row("A", []), row("B", [d(:unit_price, 3.0, :pct)])]
      assert ThresholdEvaluator.evaluate(raw_matrix, @thresholds).outcome == :approve
    end
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/invoice_approval/impl/threshold_evaluator_test.exs
```

### Step 3: Implement ThresholdEvaluator

Create `lib/showcase/invoice_approval/impl/threshold_evaluator.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Impl.ThresholdEvaluator do
  @moduledoc """
  Pure threshold-application logic. Separates business rules from the LLM:
  Claude produces raw `Discrepancy` rows; this module classifies each one
  as `:green | :amber | :red` and rolls them up to an outcome.

  Classification:
    * `:green` if `diff_value` ≤ threshold for the discrepancy's basis.
    * `:amber` if threshold < `diff_value` ≤ 2× threshold.
    * `:red` if `diff_value` > 2× threshold.
    * Out-of-contract / missing-in-invoice / other "categorical" discrepancies
      bypass thresholds and are always `:red`.

  Outcome:
    * Any `:red` row → `:reject`.
    * No `:red`, at least one `:amber` → `:needs_human`.
    * All `:green` → `:approve`.
  """

  alias Showcase.InvoiceApproval.Impl.Types.{ClassifiedDiscrepancy, Discrepancy, MatchingMatrixRow}

  @type thresholds :: %{price_pct: float(), qty_pct: float(), date_days: number()}
  @type outcome :: :approve | :reject | :needs_human

  @categorical_red [:sku_not_in_contract, :missing_in_invoice, :missing_in_delivery, :expired_contract]

  @doc "Pick the threshold for this discrepancy's field, or `nil` if categorical."
  @spec threshold_for(Discrepancy.t(), thresholds()) :: number() | nil
  def threshold_for(%Discrepancy{field: field, diff_basis: :pct}, thresholds)
      when field in [:unit_price, :total_price],
      do: thresholds.price_pct

  def threshold_for(%Discrepancy{field: :quantity, diff_basis: :pct}, thresholds),
    do: thresholds.qty_pct

  def threshold_for(%Discrepancy{field: field, diff_basis: :days}, thresholds)
      when field in [:date, :due_date, :delivery_date],
      do: thresholds.date_days

  def threshold_for(_, _), do: nil

  @spec classify_severity(Discrepancy.t(), thresholds()) :: ClassifiedDiscrepancy.severity()
  def classify_severity(%Discrepancy{field: field} = d, thresholds) do
    if field in @categorical_red do
      :red
    else
      case threshold_for(d, thresholds) do
        nil -> :red
        threshold ->
          cond do
            d.diff_value <= threshold -> :green
            d.diff_value <= 2 * threshold -> :amber
            true -> :red
          end
      end
    end
  end

  @doc """
  Apply thresholds to a raw matrix (list of row-shaped maps with raw Discrepancy
  structs in `:discrepancies`). Returns `%{outcome, classified_matrix, reasoning}`.
  """
  @spec evaluate(list(map()), thresholds()) ::
          %{outcome: outcome(), classified_matrix: list(MatchingMatrixRow.t()), reasoning: String.t()}
  def evaluate(raw_matrix, thresholds) when is_list(raw_matrix) do
    classified = Enum.map(raw_matrix, &classify_row(&1, thresholds))

    outcome = outcome_from(classified)
    reasoning = build_reasoning(outcome, classified)

    %{outcome: outcome, classified_matrix: classified, reasoning: reasoning}
  end

  defp classify_row(row, thresholds) do
    classified_discs =
      Enum.map(row.discrepancies, fn disc ->
        severity = classify_severity(disc, thresholds)
        %ClassifiedDiscrepancy{
          discrepancy: disc,
          severity: severity,
          note: build_disc_note(disc, severity, thresholds)
        }
      end)

    %MatchingMatrixRow{
      line_key: row.line_key,
      contract: row.contract,
      delivery: row.delivery,
      invoice: row.invoice,
      discrepancies: classified_discs
    }
  end

  @spec outcome_from(list(MatchingMatrixRow.t())) :: outcome()
  def outcome_from(classified_matrix) do
    severities =
      classified_matrix
      |> Enum.flat_map(& &1.discrepancies)
      |> Enum.map(& &1.severity)

    cond do
      :red in severities -> :reject
      :amber in severities -> :needs_human
      true -> :approve
    end
  end

  defp build_reasoning(:approve, _classified), do: "All lines match within configured tolerances."

  defp build_reasoning(:reject, classified) do
    worst =
      classified
      |> Enum.flat_map(fn row -> Enum.map(row.discrepancies, &{row.line_key, &1}) end)
      |> Enum.find(fn {_lk, cd} -> cd.severity == :red end)

    case worst do
      {line_key, cd} ->
        "Reject — line #{line_key} has #{cd.discrepancy.field} diff #{cd.discrepancy.diff_value} #{cd.discrepancy.diff_basis} beyond threshold. " <>
          (cd.note || "")

      nil ->
        "Reject."
    end
  end

  defp build_reasoning(:needs_human, classified) do
    amber_count =
      classified
      |> Enum.flat_map(& &1.discrepancies)
      |> Enum.count(&(&1.severity == :amber))

    "Needs human review — #{amber_count} discrepanc#{if amber_count == 1, do: "y", else: "ies"} within tolerance window."
  end

  defp build_disc_note(%Discrepancy{} = d, :green, _t),
    do: "Within tolerance (#{d.diff_value} #{d.diff_basis})"

  defp build_disc_note(%Discrepancy{} = d, :amber, _t),
    do: "Above tolerance — diff #{d.diff_value} #{d.diff_basis}"

  defp build_disc_note(%Discrepancy{} = d, :red, _t),
    do: "Significantly above tolerance — diff #{d.diff_value} #{d.diff_basis}"
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/invoice_approval/impl/threshold_evaluator_test.exs
```

Expected: 13 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/invoice_approval/impl/threshold_evaluator.ex test/showcase/invoice_approval/impl/threshold_evaluator_test.exs
git commit -m "feat(invoice_approval): ThresholdEvaluator pure module with TDD"
```

## Context

- Phase 3, Task 3. Branch: `phase-3-invoice-approval`. HEAD after T2.
- Pure module. Boundary supplies the raw matrix and thresholds — no DB, no clock.
- This is the load-bearing piece for the "slider re-runs without Claude" capability.

## Report

- Status, test count, commit SHA. Brief.

---

## Task 4: AnthropicClient fingerprint + system prompt + MockPrompts module

**Files:**
- Create: `lib/showcase/invoice_approval/mock_prompts.ex`

This task only creates the scenario data + Mock-registration helper. The Pipeline (T5) consumes the fingerprint + system prompt; tests register the scenarios.

### Step 1: Implement MockPrompts

Create `lib/showcase/invoice_approval/mock_prompts.ex`:

```elixir
defmodule Showcase.InvoiceApproval.MockPrompts do
  @moduledoc """
  Curated scenarios for the Invoice Approval demo. Each entry:
    * `name` — scenario id used as both Mock fingerprint scenario AND
      DocumentBundle.scenario field.
    * `kind` — coarse label ("clean" | "qty_mismatch" | "price_drift" | ...).
    * `client_name` — for Seed → matches a seeded client.
    * `contract_name` — matches a seeded contract.
    * `delivery_notes` / `invoice` — JSONB content stored on the bundle.
    * `thresholds` — per-bundle threshold defaults.
    * `claude_response` — canned LLM response. Returns
      `{"raw_matrix": [...rows of raw discrepancies...], "summary": "..."}`
      so `Pipeline` can parse it through `ResilientJSONParser`.
  """

  @scenarios [
    %{
      name: "clean_match",
      kind: "clean",
      client_name: "Acme Industries",
      contract_name: "Q2 2026 Hardware Order",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "delivered_on" => "2026-05-15"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "due_date" => "2026-06-15"}
        ],
        "total" => 1000.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "WGT-001", "contract": {"qty": 100, "unit_price": 10.0}, "delivery": {"qty": 100, "unit_price": 10.0}, "invoice": {"qty": 100, "unit_price": 10.0}, "discrepancies": []}], "summary": "All values match exactly."})
    },
    %{
      name: "price_drift",
      kind: "price_drift",
      client_name: "Beta Distribution",
      contract_name: "Standing PO 2026",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "BLT-M8", "qty" => 500, "unit_price" => 0.42, "delivered_on" => "2026-05-20"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "BLT-M8", "qty" => 500, "unit_price" => 0.45, "due_date" => "2026-06-20"}
        ],
        "total" => 225.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "BLT-M8", "contract": {"qty": 500, "unit_price": 0.42}, "delivery": {"qty": 500, "unit_price": 0.42}, "invoice": {"qty": 500, "unit_price": 0.45}, "discrepancies": [{"field": "unit_price", "contract_value": 0.42, "delivery_value": 0.42, "invoice_value": 0.45, "diff_value": 7.14, "diff_basis": "pct"}]}], "summary": "Invoice unit price is 7.14% higher than contract for BLT-M8."})
    },
    %{
      name: "qty_mismatch",
      kind: "qty_mismatch",
      client_name: "Gamma Engineering",
      contract_name: "2026 Hinges Frame",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "HNG-001", "qty" => 200, "unit_price" => 3.0, "delivered_on" => "2026-05-25"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "HNG-001", "qty" => 220, "unit_price" => 3.0, "due_date" => "2026-06-25"}
        ],
        "total" => 660.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "HNG-001", "contract": {"qty": 200, "unit_price": 3.0}, "delivery": {"qty": 200, "unit_price": 3.0}, "invoice": {"qty": 220, "unit_price": 3.0}, "discrepancies": [{"field": "quantity", "contract_value": 200, "delivery_value": 200, "invoice_value": 220, "diff_value": 10.0, "diff_basis": "pct"}]}], "summary": "Invoice quantity is 10% higher than delivered for HNG-001."})
    },
    %{
      name: "out_of_contract",
      kind: "out_of_contract",
      client_name: "Acme Industries",
      contract_name: "Q2 2026 Hardware Order",
      delivery_notes: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "delivered_on" => "2026-05-15"},
          %{"line_key" => "EXTRA-99", "qty" => 5, "unit_price" => 99.0, "delivered_on" => "2026-05-15"}
        ]
      },
      invoice: %{
        "items" => [
          %{"line_key" => "WGT-001", "qty" => 100, "unit_price" => 10.0, "due_date" => "2026-06-15"},
          %{"line_key" => "EXTRA-99", "qty" => 5, "unit_price" => 99.0, "due_date" => "2026-06-15"}
        ],
        "total" => 1495.0
      },
      thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
      claude_response: ~s({"raw_matrix": [{"line_key": "WGT-001", "contract": {"qty": 100, "unit_price": 10.0}, "delivery": {"qty": 100, "unit_price": 10.0}, "invoice": {"qty": 100, "unit_price": 10.0}, "discrepancies": []}, {"line_key": "EXTRA-99", "contract": null, "delivery": {"qty": 5, "unit_price": 99.0}, "invoice": {"qty": 5, "unit_price": 99.0}, "discrepancies": [{"field": "sku_not_in_contract", "contract_value": null, "delivery_value": 5, "invoice_value": 5, "diff_value": 0.0, "diff_basis": "absolute"}]}], "summary": "Line EXTRA-99 is not in the contract."})
    }
  ]

  def scenarios, do: @scenarios
end
```

### Step 2: Verify compile

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 3: Verify tests unchanged

```bash
mix test 2>&1 | tail -3
```

### Step 4: Commit

```bash
git add lib/showcase/invoice_approval/mock_prompts.ex
git commit -m "feat(invoice_approval): MockPrompts with 4 curated scenarios"
```

## Context

- Phase 3, Task 4. Branch: `phase-3-invoice-approval`. HEAD after T3.
- Pure data module. Consumed by Pipeline (T5), InvoiceApproval context (T7), and Seed (T8).

## Report

- Status, scenario count (4), commit SHA. Brief.

---

## Task 5: `ApprovalPipeline` boundary (TDD)

**Files:**
- Create: `lib/showcase/invoice_approval/pipeline.ex`
- Create: `test/showcase/invoice_approval/pipeline_test.exs`

**Contract:** `Pipeline.process_bundle(%DocumentBundle{}, ctx)` where `ctx = %{now: DateTime.t()}`:
1. Build Claude prompt from `bundle.delivery_notes` + `bundle.invoice` + the bundle's contract.
2. Call `AnthropicClient.call/2` with fingerprint `"invoice_approval:verdict:v1"` and `scenario = bundle.scenario`.
3. Parse response via `ResilientJSONParser`.
4. Translate Claude's raw discrepancies into `Discrepancy` structs.
5. Call `ThresholdEvaluator.evaluate/2` with `bundle.thresholds`.
6. Insert a new `Verdict` row inside `Ecto.Multi` (`source: "ai"`).
7. Broadcast PubSub events on `invoice_approval:processing:<bundle_id>`.

Returns `{:ok, %Verdict{}}` or `{:error, term()}`.

### Step 1: Failing test

Create `test/showcase/invoice_approval/pipeline_test.exs`:

```elixir
defmodule Showcase.InvoiceApproval.PipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Pipeline
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle, Verdict}
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, client} = Repo.insert(%Client{name: "Acme Industries"})
    {:ok, contract} =
      %Contract{}
      |> Contract.changeset(%{
        client_id: client.id,
        name: "Q2 2026 Hardware Order",
        body: %{},
        default_thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3}
      })
      |> Repo.insert()

    clean = Enum.find(MockPrompts.scenarios(), &(&1.name == "clean_match"))

    {:ok, bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: clean.name,
        kind: clean.kind,
        delivery_notes: clean.delivery_notes,
        invoice: clean.invoice,
        thresholds: clean.thresholds
      })
      |> Repo.insert()

    # Register Mock response for this scenario
    Mock.register(
      "invoice_approval:verdict:v1",
      scenario: clean.name,
      text: clean.claude_response
    )

    {:ok, %{client: client, contract: contract, bundle: bundle, scenario: clean}}
  end

  defp ctx, do: %{now: DateTime.utc_now()}

  test "process_bundle/2 returns an approved Verdict for a clean scenario",
       %{bundle: bundle} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "invoice_approval:processing:#{bundle.id}")

    {:ok, %Verdict{} = verdict} = Pipeline.process_bundle(bundle, ctx())

    assert verdict.bundle_id == bundle.id
    assert verdict.outcome == "approve"
    assert verdict.source == "ai"
    assert is_binary(verdict.reasoning)

    assert_received {:invoice_approval, :claude_returned, %{summary: _}}
    assert_received {:invoice_approval, :verdict_created, %{verdict_id: _, outcome: "approve"}}
  end

  test "process_bundle/2 returns a reject Verdict for an out-of-contract scenario",
       %{client: client, contract: contract} do
    ooc = Enum.find(MockPrompts.scenarios(), &(&1.name == "out_of_contract"))

    {:ok, bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: ooc.name,
        kind: ooc.kind,
        delivery_notes: ooc.delivery_notes,
        invoice: ooc.invoice,
        thresholds: ooc.thresholds
      })
      |> Repo.insert()

    Mock.register(
      "invoice_approval:verdict:v1",
      scenario: ooc.name,
      text: ooc.claude_response
    )

    {:ok, verdict} = Pipeline.process_bundle(bundle, ctx())
    assert verdict.outcome == "reject"
    assert verdict.reasoning =~ "EXTRA-99"
  end

  test "process_bundle/2 returns error when AnthropicClient fails (no Mock registered)",
       %{client: client, contract: contract} do
    {:ok, orphan_bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: "unregistered_scenario",
        kind: "clean",
        delivery_notes: %{"items" => []},
        invoice: %{"items" => []},
        thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3}
      })
      |> Repo.insert()

    assert {:error, _} = Pipeline.process_bundle(orphan_bundle, ctx())
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/invoice_approval/pipeline_test.exs
```

### Step 3: Implement Pipeline

Create `lib/showcase/invoice_approval/pipeline.ex`:

```elixir
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
```

### Step 4: Run until pass

```bash
mix test test/showcase/invoice_approval/pipeline_test.exs
```

Expected: 3 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/invoice_approval/pipeline.ex test/showcase/invoice_approval/pipeline_test.exs
git commit -m "feat(invoice_approval): Pipeline boundary with Claude + ThresholdEvaluator + PubSub"
```

## Context

- Phase 3, Task 5. Branch: `phase-3-invoice-approval`. HEAD after T4.
- Pipeline boundary owns the Ecto.Multi, Claude call, and PubSub broadcasts.
- Atom interning concern: `String.to_atom/1` is used to convert Claude's string field names. These atoms are bounded (a fixed set of discrepancy types), so atom-table growth isn't a DoS vector — but if you'd prefer `String.to_existing_atom/1`, make sure the relevant atoms (`:unit_price`, `:quantity`, `:due_date`, `:sku_not_in_contract`, etc.) are referenced elsewhere first so they exist in the atom table.

## Report

- Status, test count, commit SHA, any Pipeline-specific concerns.

---

## Task 6: Oban Worker (TDD)

**Files:**
- Create: `lib/showcase/invoice_approval/worker.ex`
- Create: `test/showcase/invoice_approval/worker_test.exs`

**Contract:** Oban worker on `:invoice_approval` queue. Performs given `%{"bundle_id" => id}` — fetches the bundle, runs `Pipeline.process_bundle/2`, returns `:ok` or `{:error, reason}`.

### Step 1: Failing tests

Create `test/showcase/invoice_approval/worker_test.exs`:

```elixir
defmodule Showcase.InvoiceApproval.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.InvoiceApproval.Worker
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, client} = Repo.insert(%Client{name: "Acme Industries"})
    {:ok, contract} =
      %Contract{}
      |> Contract.changeset(%{client_id: client.id, name: "Test"})
      |> Repo.insert()

    clean = Enum.find(MockPrompts.scenarios(), &(&1.name == "clean_match"))

    {:ok, bundle} =
      %DocumentBundle{}
      |> DocumentBundle.changeset(%{
        client_id: client.id,
        contract_id: contract.id,
        scenario: clean.name,
        kind: clean.kind,
        delivery_notes: clean.delivery_notes,
        invoice: clean.invoice,
        thresholds: clean.thresholds
      })
      |> Repo.insert()

    Mock.register("invoice_approval:verdict:v1",
      scenario: clean.name,
      text: clean.claude_response
    )

    {:ok, %{bundle: bundle}}
  end

  test "perform/1 returns :ok for a known bundle", %{bundle: bundle} do
    assert :ok = perform_job(Worker, %{"bundle_id" => bundle.id})
  end

  test "perform/1 returns {:error, :not_found} for unknown bundle id" do
    assert {:error, :not_found} = perform_job(Worker, %{"bundle_id" => 999_999})
  end

  test "Worker is on :invoice_approval queue" do
    assert Worker.__opts__()[:queue] == :invoice_approval
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/invoice_approval/worker_test.exs
```

### Step 3: Implement Worker

Create `lib/showcase/invoice_approval/worker.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Worker do
  @moduledoc """
  Oban worker on `:invoice_approval` queue.
  """

  use Oban.Worker, queue: :invoice_approval, max_attempts: 3

  alias Showcase.InvoiceApproval.Pipeline
  alias Showcase.InvoiceApproval.Schemas.DocumentBundle
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bundle_id" => bundle_id}}) do
    case Repo.get(DocumentBundle, bundle_id) do
      nil ->
        {:error, :not_found}

      %DocumentBundle{} = bundle ->
        case Pipeline.process_bundle(bundle, %{now: DateTime.utc_now()}) do
          {:ok, _verdict} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/invoice_approval/worker_test.exs
```

Expected: 3 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/invoice_approval/worker.ex test/showcase/invoice_approval/worker_test.exs
git commit -m "feat(invoice_approval): Oban worker on :invoice_approval queue"
```

## Report

- Status, test count, commit SHA.

---

## Task 7: `InvoiceApproval` public context

**Files:**
- Create: `lib/showcase/invoice_approval.ex`

No tests in this task — exercised via T8 Seed and T9+ LiveViews.

### Step 1: Implement context

Create `lib/showcase/invoice_approval.ex`:

```elixir
defmodule Showcase.InvoiceApproval do
  @moduledoc """
  Public context for the Invoice Approval demo.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{DocumentBundle, Verdict}
  alias Showcase.InvoiceApproval.Worker
  alias Showcase.Repo

  @doc "All seeded bundles, oldest first."
  def list_bundles do
    Repo.all(from b in DocumentBundle, order_by: [asc: b.id], preload: [:client, :contract])
  end

  @doc "Find a bundle by id with its verdict history."
  def find_bundle(id) do
    bundle = Repo.get(DocumentBundle, id) |> Repo.preload([:client, :contract])
    if bundle, do: %{bundle: bundle, verdicts: list_verdicts(bundle.id)}, else: nil
  end

  @doc "All verdicts for a bundle, latest first."
  def list_verdicts(bundle_id) do
    Repo.all(
      from v in Verdict,
        where: v.bundle_id == ^bundle_id,
        order_by: [desc: v.inserted_at]
    )
  end

  @doc "Latest verdict for a bundle, or nil."
  def latest_verdict(bundle_id) do
    Repo.one(
      from v in Verdict,
        where: v.bundle_id == ^bundle_id,
        order_by: [desc: v.inserted_at],
        limit: 1
    )
  end

  @doc "Enqueue an Oban job to process this bundle."
  def enqueue(bundle_id) when is_integer(bundle_id) do
    Worker.new(%{bundle_id: bundle_id}) |> Oban.insert()
  end

  @doc """
  Register Mock responses for every scenario in `MockPrompts.scenarios/0`.
  Idempotent — re-running just overwrites the same keys.
  """
  def register_mock_responses do
    Enum.each(MockPrompts.scenarios(), fn s ->
      Mock.register("invoice_approval:verdict:v1",
        scenario: s.name,
        text: s.claude_response
      )
    end)
  end

  @doc """
  Write a manual verdict override. Creates a new `Verdict` row with
  `source: "override"` AND an entry in `Showcase.Common.AuditLog`.
  """
  def override_verdict(bundle_id, outcome, reason, actor)
      when outcome in ["approve", "reject", "needs_human"] do
    case latest_verdict(bundle_id) do
      nil ->
        {:error, :no_prior_verdict}

      latest ->
        attrs = %{
          bundle_id: bundle_id,
          outcome: outcome,
          reasoning: "Override: #{reason}",
          raw_matrix: latest.raw_matrix,
          classified_matrix: latest.classified_matrix,
          thresholds_used: latest.thresholds_used,
          source: "override",
          actor: actor
        }

        Repo.transaction(fn ->
          {:ok, override} = %Verdict{} |> Verdict.changeset(attrs) |> Repo.insert()

          Showcase.Common.AuditLog
          |> Ash.Changeset.for_create(:write, %{
            demo: "invoice_approval",
            entity_type: "bundle",
            entity_id: to_string(bundle_id),
            event: "verdict_override",
            payload: %{
              from: latest.outcome,
              to: outcome,
              reason: reason
            },
            actor: actor
          })
          |> Ash.create()

          override
        end)
    end
  end
end
```

### Step 2: Verify compile

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 3: Verify tests unchanged

```bash
mix test 2>&1 | tail -3
```

### Step 4: Commit

```bash
git add lib/showcase/invoice_approval.ex
git commit -m "feat(invoice_approval): public context with bundle queries + override action"
```

## Report

- Status, compile result, commit SHA.

---

## Task 8: `InvoiceApproval.Seed` (TDD)

**Files:**
- Create: `lib/showcase/invoice_approval/seed.ex`
- Create: `test/showcase/invoice_approval/seed_test.exs`

**Contract:** Implements `Showcase.Common.DemoSeeder`. Seeds clients, contracts, and a DocumentBundle for each scenario in `MockPrompts.scenarios/0`. Idempotent.

### Step 1: Failing tests

Create `test/showcase/invoice_approval/seed_test.exs`:

```elixir
defmodule Showcase.InvoiceApproval.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.InvoiceApproval.Seed
  alias Showcase.Repo

  test "name/0 returns 'Invoice Approval'" do
    assert Seed.name() == "Invoice Approval"
  end

  test "description/0 returns value-framing copy" do
    desc = Seed.description()
    assert is_binary(desc)
    assert String.length(desc) > 20
  end

  test "oban_queue/0 returns :invoice_approval" do
    assert Seed.oban_queue() == :invoice_approval
  end

  test "tables/0 returns ia_* tables children-before-parents" do
    tables = Seed.tables()
    assert "ia_verdicts" in tables
    assert "ia_document_bundles" in tables
    assert "ia_contracts" in tables
    assert "ia_clients" in tables
    assert Enum.find_index(tables, &(&1 == "ia_verdicts")) <
             Enum.find_index(tables, &(&1 == "ia_document_bundles"))
  end

  test "seed/0 populates clients, contracts, bundles" do
    assert :ok = Seed.seed()
    assert Repo.aggregate(Client, :count) >= 3
    assert Repo.aggregate(Contract, :count) >= 3
    assert Repo.aggregate(DocumentBundle, :count) >= 4
  end

  test "seed/0 is idempotent" do
    assert :ok = Seed.seed()
    counts_a = {Repo.aggregate(Client, :count), Repo.aggregate(Contract, :count), Repo.aggregate(DocumentBundle, :count)}
    assert :ok = Seed.seed()
    counts_b = {Repo.aggregate(Client, :count), Repo.aggregate(Contract, :count), Repo.aggregate(DocumentBundle, :count)}
    assert counts_a == counts_b
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/invoice_approval/seed_test.exs
```

### Step 3: Implement Seed

Create `lib/showcase/invoice_approval/seed.ex`:

```elixir
defmodule Showcase.InvoiceApproval.Seed do
  @moduledoc """
  Seeds the Invoice Approval demo with clients, contracts, and
  document bundles for each `MockPrompts.scenarios/0` entry.

  Idempotent.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.InvoiceApproval.MockPrompts
  alias Showcase.InvoiceApproval.Schemas.{Client, Contract, DocumentBundle}
  alias Showcase.Repo

  @impl true
  def name, do: "Invoice Approval"

  @impl true
  def description do
    "Three-way matching of contract, delivery note, and invoice. Configurable thresholds; explainable verdicts; override + audit-trail loop."
  end

  @impl true
  def oban_queue, do: :invoice_approval

  @impl true
  def tables do
    ["ia_verdicts", "ia_document_bundles", "ia_contracts", "ia_clients"]
  end

  @impl true
  def seed do
    Repo.transaction(fn ->
      seed_clients_and_contracts()
      seed_bundles()
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_clients_and_contracts do
    MockPrompts.scenarios()
    |> Enum.map(fn s -> {s.client_name, s.contract_name} end)
    |> Enum.uniq()
    |> Enum.each(fn {client_name, contract_name} ->
      client =
        case Repo.get_by(Client, name: client_name) do
          nil ->
            {:ok, c} = Repo.insert(%Client{name: client_name, contact: "ops@#{slug(client_name)}.example"})
            c
          existing -> existing
        end

      unless Repo.get_by(Contract, client_id: client.id, name: contract_name) do
        %Contract{}
        |> Contract.changeset(%{
          client_id: client.id,
          name: contract_name,
          body: %{"line_items" => []},
          default_thresholds: %{"price_pct" => 5.0, "qty_pct" => 2.0, "date_days" => 3},
          valid_from: ~D[2026-01-01],
          valid_until: ~D[2026-12-31]
        })
        |> Repo.insert!()
      end
    end)
  end

  defp seed_bundles do
    Enum.each(MockPrompts.scenarios(), fn s ->
      client = Repo.get_by!(Client, name: s.client_name)
      contract = Repo.get_by!(Contract, client_id: client.id, name: s.contract_name)

      unless Repo.get_by(DocumentBundle, scenario: s.name) do
        %DocumentBundle{}
        |> DocumentBundle.changeset(%{
          client_id: client.id,
          contract_id: contract.id,
          scenario: s.name,
          kind: s.kind,
          delivery_notes: s.delivery_notes,
          invoice: s.invoice,
          thresholds: s.thresholds
        })
        |> Repo.insert!()
      end
    end)
  end

  defp slug(s) do
    s
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/[^a-z0-9\-]/, "")
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/invoice_approval/seed_test.exs
```

Expected: 6 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/invoice_approval/seed.ex test/showcase/invoice_approval/seed_test.exs
git commit -m "feat(invoice_approval): Seed implementing DemoSeeder with idempotent inserts"
```

## Report

- Status, test count, commit SHA.

---

## Task 9: `MatchingMatrix` function component

**Files:**
- Create: `lib/showcase_web/live/invoice_approval/components/matching_matrix.ex`

Function component — no unit tests; exercised in T11 + T12 LiveView tests.

### Step 1: Create the component

Create `lib/showcase_web/live/invoice_approval/components/matching_matrix.ex`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.Components.MatchingMatrix do
  @moduledoc """
  Renders the 3-column Contract / Delivery / Invoice matching matrix.

  Each row shows the line_key, per-doc values, and any classified
  discrepancies with severity-colored badges.
  """

  use Phoenix.Component

  attr :rows, :list, required: true,
    doc: "List of maps shaped like classified_matrix from Pipeline output"

  def matching_matrix(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm border-collapse">
        <thead class="bg-zinc-100 text-zinc-600 uppercase text-xs tracking-wide">
          <tr>
            <th class="py-2 px-3 text-left">Line</th>
            <th class="py-2 px-3 text-left">Contract</th>
            <th class="py-2 px-3 text-left">Delivery Note</th>
            <th class="py-2 px-3 text-left">Invoice</th>
            <th class="py-2 px-3 text-left">Discrepancies</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class={["border-t", row_bg(row)]}>
            <td class="py-3 px-3 font-mono text-xs">{row["line_key"]}</td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["contract"]} /></td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["delivery"]} /></td>
            <td class="py-3 px-3 align-top text-xs"><.cell map={row["invoice"]} /></td>
            <td class="py-3 px-3 align-top">
              <ul :if={row["discrepancies"] not in [nil, []]} class="space-y-1">
                <li :for={cd <- row["discrepancies"]}>
                  <span class={severity_badge(cd["severity"])}>{cd["severity"]}</span>
                  <span class="ml-2 text-xs">{cd["discrepancy"]["field"]} · {cd["note"]}</span>
                </li>
              </ul>
              <span :if={row["discrepancies"] in [nil, []]} class="text-xs text-emerald-600">✓ match</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp cell(assigns) do
    assigns = assign_new(assigns, :map, fn -> %{} end)

    ~H"""
    <%= if @map in [nil, %{}] do %>
      <span class="text-zinc-400">—</span>
    <% else %>
      <ul class="font-mono text-xs space-y-0.5">
        <li :for={{k, v} <- @map}>{k}: {format_value(v)}</li>
      </ul>
    <% end %>
    """
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_value(v), do: to_string(v)

  defp row_bg(%{"discrepancies" => discs}) when is_list(discs) and discs != [] do
    severities = Enum.map(discs, & &1["severity"])

    cond do
      "red" in severities -> "bg-red-50"
      "amber" in severities -> "bg-amber-50"
      true -> "bg-emerald-50"
    end
  end

  defp row_bg(_), do: "bg-emerald-50"

  defp severity_badge("green"),
    do: "inline-block rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-emerald-300"

  defp severity_badge("amber"),
    do: "inline-block rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-900 ring-1 ring-amber-300"

  defp severity_badge("red"),
    do: "inline-block rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-900 ring-1 ring-red-300"

  defp severity_badge(_), do: "inline-block rounded-full bg-zinc-100 px-2 py-0.5 text-xs"
end
```

### Step 2: Compile clean

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 3: Commit

```bash
git add lib/showcase_web/live/invoice_approval/components/matching_matrix.ex
git commit -m "feat(web): MatchingMatrix 3-column component with severity coloring"
```

## Report

- Status, compile result, commit SHA. Brief.

---

## Task 10: `ThresholdSliders` function component

**Files:**
- Create: `lib/showcase_web/live/invoice_approval/components/threshold_sliders.ex`

### Step 1: Create the component

Create `lib/showcase_web/live/invoice_approval/components/threshold_sliders.ex`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.Components.ThresholdSliders do
  @moduledoc """
  Three range sliders that drive `phx-change="update_thresholds"`.
  The parent LiveView re-evaluates the matrix on each change.
  """

  use Phoenix.Component

  attr :thresholds, :map, required: true,
    doc: ~s(map with "price_pct", "qty_pct", "date_days" keys)

  def threshold_sliders(assigns) do
    ~H"""
    <form phx-change="update_thresholds" class="space-y-4">
      <div>
        <label class="block text-xs uppercase tracking-wide text-zinc-500">
          Price tolerance: {(@thresholds["price_pct"] || 5.0)}%
        </label>
        <input
          type="range"
          name="price_pct"
          min="0"
          max="20"
          step="0.5"
          value={@thresholds["price_pct"] || 5.0}
          class="w-full"
        />
      </div>

      <div>
        <label class="block text-xs uppercase tracking-wide text-zinc-500">
          Quantity tolerance: {(@thresholds["qty_pct"] || 2.0)}%
        </label>
        <input
          type="range"
          name="qty_pct"
          min="0"
          max="20"
          step="0.5"
          value={@thresholds["qty_pct"] || 2.0}
          class="w-full"
        />
      </div>

      <div>
        <label class="block text-xs uppercase tracking-wide text-zinc-500">
          Date tolerance: {(@thresholds["date_days"] || 3)} days
        </label>
        <input
          type="range"
          name="date_days"
          min="0"
          max="30"
          step="1"
          value={@thresholds["date_days"] || 3}
          class="w-full"
        />
      </div>
    </form>
    """
  end
end
```

### Step 2: Compile + commit

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
git add lib/showcase_web/live/invoice_approval/components/threshold_sliders.ex
git commit -m "feat(web): ThresholdSliders function component with phx-change"
```

## Report

- Status, commit SHA. Brief.

---

## Task 11: `QueueLive` at `/invoice-approval`

**Files:**
- Create: `lib/showcase_web/live/invoice_approval/queue_live.ex`
- Create: `test/showcase_web/live/invoice_approval/queue_live_test.exs`
- Modify: `lib/showcase_web/router.ex` (add route)

### Step 1: Failing tests

Create `test/showcase_web/live/invoice_approval/queue_live_test.exs`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.QueueLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.InvoiceApproval.Seed

  setup do
    Seed.seed()
    :ok
  end

  test "renders the queue at /invoice-approval", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invoice-approval")

    assert html =~ "Invoice Approval"
    assert html =~ "Bundle"  # column heading or label somewhere
  end

  test "shows seeded scenarios", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invoice-approval")

    assert html =~ "clean_match"
    assert html =~ "price_drift"
    assert html =~ "qty_mismatch"
    assert html =~ "out_of_contract"
  end
end
```

### Step 2: Add route

In `lib/showcase_web/router.ex`, public scope, add (alongside existing OrderFlow routes):

```elixir
live "/invoice-approval", InvoiceApproval.QueueLive
live "/invoice-approval/bundles/:id", InvoiceApproval.BundleDetailLive
```

### Step 3: Implement QueueLive

Create `lib/showcase_web/live/invoice_approval/queue_live.ex`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.QueueLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and
         Application.get_env(:showcase, :anthropic_client_impl) ==
           Showcase.Common.AnthropicClient.Mock do
      InvoiceApproval.register_mock_responses()
    end

    {:ok,
     socket
     |> assign(:page_title, "Invoice Approval")
     |> assign(:bundles, InvoiceApproval.list_bundles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Invoice Approval</h1>
            <p class="text-sm text-zinc-500 mt-1">
              3-way matching across contract, delivery note, and invoice.
            </p>
          </div>
          <a href="/" class="text-sm text-zinc-500 underline">&larr; Dashboard</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Bundles</h2>
        <ul class="space-y-2">
          <li :for={bundle <- @bundles} class="rounded border bg-white p-3 flex items-center justify-between">
            <div>
              <p class="font-medium text-sm">{bundle.client.name} · <span class="font-mono">{bundle.scenario}</span></p>
              <p class="text-xs text-zinc-500 mt-1">{bundle.contract.name} · kind: {bundle.kind}</p>
            </div>
            <a
              href={"/invoice-approval/bundles/#{bundle.id}"}
              class="text-sm font-medium text-emerald-700"
            >
              Open →
            </a>
          </li>
        </ul>
      </main>
    </div>
    """
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase_web/live/invoice_approval/queue_live_test.exs 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase_web/live/invoice_approval/queue_live.ex lib/showcase_web/router.ex test/showcase_web/live/invoice_approval/queue_live_test.exs
git commit -m "feat(web): InvoiceApproval.QueueLive at /invoice-approval"
```

## Report

- Status, test count, commit SHA.

---

## Task 12: `BundleDetailLive` (the centerpiece — TDD)

**Files:**
- Create: `lib/showcase_web/live/invoice_approval/bundle_detail_live.ex`
- Create: `test/showcase_web/live/invoice_approval/bundle_detail_live_test.exs`

**Contract:**
- Mount: fetches bundle + latest verdict. If no verdict, enqueues Worker.
- Subscribes to `invoice_approval:processing:<id>` PubSub topic.
- Renders 3-column matrix + threshold sliders + verdict outcome + override button.
- `phx-change="update_thresholds"` → re-evaluates raw_matrix locally via `ThresholdEvaluator`, creates new Verdict row with `source: "ai"` (since the matrix is still Claude's, only thresholds changed).
- `phx-click="override"` with `value` of new outcome → calls `InvoiceApproval.override_verdict/4`.

### Step 1: Failing tests

Create `test/showcase_web/live/invoice_approval/bundle_detail_live_test.exs`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.BundleDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  import Phoenix.LiveViewTest

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.InvoiceApproval
  alias Showcase.InvoiceApproval.Schemas.Verdict
  alias Showcase.InvoiceApproval.Seed
  alias Showcase.Repo

  setup do
    Mock.reset()
    InvoiceApproval.register_mock_responses()
    Seed.seed()

    bundle = Repo.get_by!(Showcase.InvoiceApproval.Schemas.DocumentBundle, scenario: "clean_match")

    # Pre-run pipeline so there's a verdict
    {:ok, _} = InvoiceApproval.enqueue(bundle.id)
    Oban.drain_queue(queue: :invoice_approval)

    {:ok, %{bundle: bundle}}
  end

  test "renders the bundle detail page", %{conn: conn, bundle: bundle} do
    {:ok, _view, html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    assert html =~ "Bundle ##{bundle.id}"
    assert html =~ "WGT-001"
  end

  test "shows the latest verdict outcome", %{conn: conn, bundle: bundle} do
    {:ok, _view, html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    assert html =~ "approve"
  end

  test "updating thresholds creates a new verdict with the new thresholds_used",
       %{conn: conn, bundle: bundle} do
    {:ok, view, _html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    initial_count = Repo.aggregate(Verdict, :count, :id)

    render_change(view, "update_thresholds", %{
      "price_pct" => "10.0",
      "qty_pct" => "5.0",
      "date_days" => "7"
    })

    assert Repo.aggregate(Verdict, :count, :id) == initial_count + 1

    new_latest = InvoiceApproval.latest_verdict(bundle.id)
    assert new_latest.thresholds_used == %{"price_pct" => 10.0, "qty_pct" => 5.0, "date_days" => 7}
    assert new_latest.source == "ai"
  end

  test "override creates a new verdict with source: 'override' + audit log", %{conn: conn, bundle: bundle} do
    {:ok, view, _html} = live(conn, "/invoice-approval/bundles/#{bundle.id}")

    render_click(view, "override", %{"outcome" => "reject", "reason" => "manual reject"})

    new_latest = InvoiceApproval.latest_verdict(bundle.id)
    assert new_latest.source == "override"
    assert new_latest.outcome == "reject"
    assert new_latest.reasoning =~ "manual reject"

    # Audit log entry written
    {:ok, audit_entries} =
      Showcase.Common.AuditLog.for_entity("invoice_approval", "bundle", to_string(bundle.id))

    assert Enum.any?(audit_entries, &(&1.event == "verdict_override"))
  end
end
```

### Step 2: Implement BundleDetailLive

Create `lib/showcase_web/live/invoice_approval/bundle_detail_live.ex`:

```elixir
defmodule ShowcaseWeb.InvoiceApproval.BundleDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.InvoiceApproval
  alias Showcase.InvoiceApproval.Impl.ThresholdEvaluator
  alias Showcase.InvoiceApproval.Schemas.Verdict
  alias Showcase.Repo
  alias ShowcaseWeb.InvoiceApproval.Components.{MatchingMatrix, ThresholdSliders}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bundle_id = String.to_integer(id)

    case InvoiceApproval.find_bundle(bundle_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/invoice-approval")}

      %{bundle: bundle, verdicts: verdicts} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Showcase.PubSub, "invoice_approval:processing:#{bundle.id}")

          # If no verdict yet, enqueue a run
          if verdicts == [] do
            InvoiceApproval.enqueue(bundle.id)
          end
        end

        {:ok,
         socket
         |> assign(:page_title, "Bundle ##{bundle.id}")
         |> assign(:bundle, bundle)
         |> assign(:latest_verdict, List.first(verdicts))
         |> assign(:thresholds, bundle.thresholds)
         |> assign(:override_reason, "")}
    end
  end

  @impl true
  def handle_event("update_thresholds", params, socket) do
    new_thresholds =
      socket.assigns.thresholds
      |> Map.put("price_pct", to_float(params["price_pct"]))
      |> Map.put("qty_pct", to_float(params["qty_pct"]))
      |> Map.put("date_days", to_int(params["date_days"]))

    re_evaluate_with(socket, new_thresholds)
  end

  def handle_event("override", %{"outcome" => outcome, "reason" => reason}, socket) do
    case InvoiceApproval.override_verdict(socket.assigns.bundle.id, outcome, reason, "admin") do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:latest_verdict, InvoiceApproval.latest_verdict(socket.assigns.bundle.id))
         |> put_flash(:info, "Override recorded.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Override failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:invoice_approval, :verdict_created, %{verdict_id: id}}, socket) do
    verdict = Repo.get!(Verdict, id)
    {:noreply, assign(socket, :latest_verdict, verdict)}
  end

  def handle_info({:invoice_approval, _event, _payload}, socket), do: {:noreply, socket}

  # Re-evaluate the same raw_matrix with new thresholds, write a new verdict.
  defp re_evaluate_with(socket, new_thresholds) do
    bundle = socket.assigns.bundle

    case socket.assigns.latest_verdict do
      nil ->
        {:noreply, socket}

      latest ->
        raw_matrix = denormalize(latest.raw_matrix["rows"] || [])
        eval =
          ThresholdEvaluator.evaluate(raw_matrix, %{
            price_pct: new_thresholds["price_pct"],
            qty_pct: new_thresholds["qty_pct"],
            date_days: new_thresholds["date_days"]
          })

        classified_json =
          %{"rows" => Enum.map(eval.classified_matrix, &classified_row_to_json/1)}

        attrs = %{
          bundle_id: bundle.id,
          outcome: Atom.to_string(eval.outcome),
          reasoning: eval.reasoning,
          raw_matrix: latest.raw_matrix,
          classified_matrix: classified_json,
          thresholds_used: new_thresholds,
          source: "ai",
          actor: nil
        }

        {:ok, new_verdict} = %Verdict{} |> Verdict.changeset(attrs) |> Repo.insert()

        {:noreply,
         socket
         |> assign(:thresholds, new_thresholds)
         |> assign(:latest_verdict, new_verdict)}
    end
  end

  defp denormalize(rows) do
    Enum.map(rows, fn r ->
      %{
        line_key: r["line_key"],
        contract: r["contract"] || %{},
        delivery: r["delivery"] || %{},
        invoice: r["invoice"] || %{},
        discrepancies:
          (r["discrepancies"] || [])
          |> Enum.map(fn d ->
            %Showcase.InvoiceApproval.Impl.Types.Discrepancy{
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

  defp classified_row_to_json(row) do
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
  end

  defp to_float(v) when is_binary(v), do: String.to_float(v)
  defp to_float(v) when is_number(v), do: v * 1.0
  defp to_float(_), do: 0.0

  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(v) when is_integer(v), do: v
  defp to_int(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-xl font-semibold">Bundle #{@bundle.id}</h1>
            <p class="text-sm text-zinc-500 mt-1">
              {@bundle.client.name} · <span class="font-mono">{@bundle.scenario}</span>
            </p>
          </div>
          <a href="/invoice-approval" class="text-sm text-zinc-500 underline">&larr; Queue</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section class="lg:col-span-2 space-y-6">
          <h2 class="text-sm uppercase tracking-wide text-zinc-500">Matching Matrix</h2>
          <%= if @latest_verdict do %>
            <MatchingMatrix.matching_matrix rows={@latest_verdict.classified_matrix["rows"] || []} />
          <% else %>
            <p class="text-sm text-zinc-500">Awaiting AI verdict… (refresh in a few seconds)</p>
          <% end %>
        </section>

        <aside class="space-y-6">
          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Verdict</h2>
            <%= if @latest_verdict do %>
              <p class="text-lg font-semibold">
                <span class={outcome_badge(@latest_verdict.outcome)}>
                  {String.upcase(@latest_verdict.outcome)}
                </span>
              </p>
              <p class="mt-2 text-sm text-zinc-700">{@latest_verdict.reasoning}</p>
              <p class="mt-2 text-xs text-zinc-500">
                source: <span class="font-mono">{@latest_verdict.source}</span>
              </p>
            <% else %>
              <p class="text-sm text-zinc-500">Pending.</p>
            <% end %>
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Thresholds</h2>
            <ThresholdSliders.threshold_sliders thresholds={@thresholds} />
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-3">Override</h2>
            <form phx-submit="override" class="space-y-2">
              <select name="outcome" class="w-full rounded border-zinc-300 text-sm">
                <option value="approve">Approve</option>
                <option value="reject">Reject</option>
                <option value="needs_human">Needs Human</option>
              </select>
              <input
                type="text"
                name="reason"
                placeholder="Reason for override"
                class="w-full rounded border-zinc-300 text-sm"
                required
              />
              <button
                type="submit"
                class="rounded bg-zinc-800 px-3 py-2 text-xs font-medium text-white hover:bg-zinc-900"
              >
                Override verdict
              </button>
            </form>
          </div>
        </aside>
      </main>
    </div>
    """
  end

  defp outcome_badge("approve"),
    do: "inline-block rounded-full bg-emerald-100 px-3 py-1 text-emerald-800 ring-1 ring-emerald-300"

  defp outcome_badge("reject"),
    do: "inline-block rounded-full bg-red-100 px-3 py-1 text-red-900 ring-1 ring-red-300"

  defp outcome_badge("needs_human"),
    do: "inline-block rounded-full bg-amber-100 px-3 py-1 text-amber-900 ring-1 ring-amber-300"

  defp outcome_badge(_),
    do: "inline-block rounded-full bg-zinc-100 px-3 py-1"
end
```

### Step 3: Run until pass

```bash
mix test test/showcase_web/live/invoice_approval/bundle_detail_live_test.exs 2>&1 | tail -10
```

Expected: 4 tests, 0 failures.

### Step 4: Commit

```bash
git add lib/showcase_web/live/invoice_approval/bundle_detail_live.ex test/showcase_web/live/invoice_approval/bundle_detail_live_test.exs
git commit -m "feat(web): BundleDetailLive with matrix + sliders + verdict + override"
```

## Context

- Phase 3, Task 12. Branch: `phase-3-invoice-approval`. HEAD after T11.
- This is the centerpiece LiveView. It exercises ThresholdEvaluator (slider re-eval), Pipeline (initial run on mount if no verdict), AuditLog (via override), MatchingMatrix + ThresholdSliders components.

## Report

- Status, test count, commit SHA, any HEEx adjustments needed.

---

## Task 13: Update TileConfig — flip Invoice Approval to `:live`

**Files:**
- Modify: `lib/showcase/dashboard/tile_config.ex`
- Modify: `test/showcase/dashboard/tile_config_test.exs` (update assertion for invoice_approval)

### Step 1: Update the tile

Open `lib/showcase/dashboard/tile_config.ex`. Find the `:invoice_approval` entry and update it:

```elixir
%Tile{
  id: :invoice_approval,
  title: "Invoice Approval",
  description:
    "Three-way matching across contract, delivery note, and invoice. AI verdicts are explainable; configurable tolerances drive the routing.",
  roi_hook: "AP clerks see only the ambiguous middle; configuration is the dial.",
  status: :live,
  path: "/invoice-approval",
  seeder: Showcase.InvoiceApproval.Seed
}
```

### Step 2: Update the TileConfig test

Open `test/showcase/dashboard/tile_config_test.exs`. Find the test `"OrderFlow is live; the rest are coming_soon"` and replace it with two tests:

```elixir
    test "OrderFlow and Invoice Approval are live" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      assert by_id[:order_flow].status == :live
      assert by_id[:order_flow].path == "/order-flow"
      assert by_id[:order_flow].seeder == Showcase.OrderFlow.Seed

      assert by_id[:invoice_approval].status == :live
      assert by_id[:invoice_approval].path == "/invoice-approval"
      assert by_id[:invoice_approval].seeder == Showcase.InvoiceApproval.Seed
    end

    test "RecruitFlow, Planogram, Restaurant Compliance are coming_soon" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      Enum.each([:recruit_flow, :planogram, :restaurant_compliance], fn id ->
        assert by_id[id].status == :coming_soon
        assert by_id[id].path == nil
        assert by_id[id].seeder == nil
      end)
    end
```

### Step 3: Run tests

```bash
mix test test/showcase/dashboard/tile_config_test.exs 2>&1 | tail -5
mix test test/showcase/dashboard_test.exs 2>&1 | tail -5
mix test test/showcase_web/live/dashboard_live_test.exs 2>&1 | tail -5
```

Expected: all green. The dashboard now shows Invoice Approval as Live.

### Step 4: Verify ResetLive picks it up

```bash
mix test test/showcase_web/live/admin/reset_live_test.exs 2>&1 | tail -5
```

Expected: green. Admin reset page now has buttons for OrderFlow AND Invoice Approval.

### Step 5: Commit

```bash
git add lib/showcase/dashboard/tile_config.ex test/showcase/dashboard/tile_config_test.exs
git commit -m "feat(dashboard): flip Invoice Approval tile from coming_soon to live"
```

## Report

- Status, test results, commit SHA.

---

## Task 14: Wire seed.exs to also seed Invoice Approval

**Files:**
- Modify: `priv/repo/seeds.exs`

### Step 1: Update seeds.exs

Open `priv/repo/seeds.exs`. Replace its contents with:

```elixir
# Script for populating the database. Run with:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent — re-running produces identical baseline state.

require Logger

# Seed all live demos. Adding a new live demo to TileConfig auto-includes it here.
Showcase.Dashboard.live_seeders()
|> Enum.each(fn seeder ->
  Logger.info("Seeding #{seeder.name()}...")

  case seeder.seed() do
    :ok ->
      Logger.info("#{seeder.name()} seeded.")

    {:error, reason} ->
      Logger.error("#{seeder.name()} seed failed: #{inspect(reason)}")
      System.halt(1)
  end
end)

Logger.info("All live demos seeded. Visit http://localhost:4321/")
```

### Step 2: Run seeds

```bash
mix run priv/repo/seeds.exs 2>&1 | tail -10
```

Expected: log lines for OrderFlow + Invoice Approval seeding.

### Step 3: Commit

```bash
git add priv/repo/seeds.exs
git commit -m "chore: generalize seeds.exs to enumerate Dashboard.live_seeders/0"
```

## Report

- Status, log lines from the seed run, commit SHA.

---

## Task 15: Final smoke test + phase-3 tag

Verification task. No new code.

### Step 1: Full test suite

```bash
mix test 2>&1 | tail -5
```

Expected: 1 property + ~165 tests, 0 failures (Phase 2 was ~132; Phase 3 adds ~33 tests).

### Step 2: Compile clean

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 3: Boot + verify routes

If Phoenix dev server is running in background, just curl. Otherwise start one:

```bash
PORT=4321 mix phx.server &
SERVER_PID=$!
sleep 3

echo "GET /                                          → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/)"
echo "GET /order-flow                                → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/order-flow)"
echo "GET /invoice-approval                          → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/invoice-approval)"
echo "GET /invoice-approval/bundles/1                → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/invoice-approval/bundles/1)"
echo "GET /admin/reset auth                          → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4321/admin/reset)"

kill $SERVER_PID 2>/dev/null
```

Expected:
- `/` → 200 (dashboard now shows Invoice Approval as Live)
- `/order-flow` → 200
- `/invoice-approval` → 200
- `/invoice-approval/bundles/1` → 200
- `/admin/reset` (auth) → 200

### Step 4: Tag

```bash
git tag -a phase-3 -m "Phase 3 Invoice Approval complete: 3-way matching demo, live threshold sliders, override + audit"
git tag -l 'phase-*'
```

Expected: `phase-0`, `phase-1`, `phase-2`, `phase-3` all listed.

### Step 5: History snapshot

```bash
git log --oneline phase-2..HEAD
```

## Report

- Status
- Test count
- Route responses
- Tag confirmation
- Commit history
- Anything unexpected

---

## Phase 3 acceptance criteria

When all 15 tasks are complete and committed:

- [ ] `mix test` green; full suite ~165 tests
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `GET /invoice-approval` renders the bundle queue (200)
- [ ] `GET /invoice-approval/bundles/:id` renders matrix + sliders + verdict + override UI (200)
- [ ] Moving a threshold slider creates a new `Verdict` row with `source: "ai"` (re-evaluates without Claude call)
- [ ] Override creates a `Verdict` row with `source: "override"` AND writes `AuditLog` entry
- [ ] Dashboard `/` shows Invoice Approval tile as `:live`
- [ ] `/admin/reset` has a "Reset Invoice Approval" button (enumerated from `Dashboard.live_seeders/0`)
- [ ] `phase-3` tag in git history

The next plan (Phase 4: RecruitFlow) will be the third live demo. Updating the RecruitFlow tile from `:coming_soon` to `:live` continues to be a single-line change.
