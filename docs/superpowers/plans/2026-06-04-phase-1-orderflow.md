# Phase 1: OrderFlow Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the OrderFlow demo end-to-end. An AE clicks `Generate order` in a LiveView; a synthetic customer message runs through the real AI pipeline (extract → identify client → 5-step cascade-match each line → create Order); the audience sees each stage light up live, the per-line cascade step + confidence, and can correct a mismatch to demonstrate the self-improving alias loop in action.

**Architecture:** Plain Ecto schemas under the `of_*` table prefix; pure functions in `lib/showcase/order_flow/impl/` (normalize, confidence decay, alias promotion); cascade step modules implementing `Showcase.Common.CascadeMatcher.Step` for each of the 5 priority levels; `OrderFlow.Pipeline` boundary owning `Ecto.Multi`, AnthropicClient calls, and PubSub stage broadcasts; Oban worker on the `:order_flow` queue; LiveView using the Phase 0 shared components (PipelineStages, CascadeMatrix, NeedsHumanBadge, JSONInspector).

**Tech Stack:**
- Builds on Phase 0 (`phase-0` tag at `a0db827`, merged to main at `8e898ed`)
- Plain Ecto for schemas (Client, Product, ProductAlias, Order, OrderLine, SyntheticMessage)
- `Showcase.Common.AnthropicClient` (Mock in tests, Live in dev/prod)
- `Showcase.Common.CascadeMatcher` (engine + per-step modules in `order_flow/cascade/`)
- `Showcase.Common.ResilientJSONParser` (Claude response parsing)
- `Showcase.Common.NeedsHuman` (low-confidence flagging)
- Oban `:order_flow` queue (configured in Phase 0)
- Postgres `pg_trgm` (enabled in Phase 0) for fuzzy step
- LiveView + Phoenix.PubSub for live stage broadcasts

**Reference spec:** `docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md` §4.1

---

## File structure produced by this phase

```
lib/
  showcase/
    order_flow.ex                       # public context: enqueue, find_message, list_messages
    order_flow/
      schemas/
        client.ex                       # Ecto: of_clients (id, name, email, phone)
        product.ex                      # Ecto: of_products (id, sku, name, normalized_name)
        product_alias.ex                # Ecto: of_product_aliases (normalized_text, product_id,
                                        #                            client_id NULL=global,
                                        #                            confidence, last_used_at,
                                        #                            source, use_count)
        order.ex                        # Ecto: of_orders (id, client_id, status, message_id)
        order_line.ex                   # Ecto: of_order_lines (id, order_id, product_id NULL,
                                        #                       raw_description, quantity,
                                        #                       confidence, match_step)
        synthetic_message.ex            # Ecto: of_synthetic_messages (id, body, kind, scenario)
      impl/
        normalize.ex                    # pure: normalize_text/1
        confidence_decay.ex             # pure: decay/2 (raw_confidence, last_used_at, now)
        alias_promotion.ex              # pure: eligible_for_global?/1
      cascade/
        exact_step.ex                   # CascadeMatcher.Step impl
        fuzzy_trigram_step.ex           # CascadeMatcher.Step impl (pg_trgm)
        client_alias_step.ex            # CascadeMatcher.Step impl (client-scoped alias)
        global_alias_step.ex            # CascadeMatcher.Step impl (client_id IS NULL)
        claude_fallback_step.ex         # CascadeMatcher.Step impl (AnthropicClient)
      extraction.ex                     # boundary: call AnthropicClient + parse to %{client, lines}
      client_resolver.ex                # boundary: by client_hint -> Client or :needs_human
      pipeline.ex                       # boundary: process_message/2
      worker.ex                         # Oban worker on :order_flow queue
      seed.ex                           # @behaviour DemoSeeder + oban_queue/0
      mock_prompts.ex                   # test-only: registers Mock canned responses

  showcase_web/
    live/
      order_flow/
        inbox_live.ex                   # the OrderFlow demo LiveView
        components/
          inbox_pane.ex                 # left: list of seeded messages
          pipeline_pane.ex              # right: PipelineStages + CascadeMatrix per line
          order_review.ex               # bottom: order lines + correction UI

priv/repo/migrations/
  <ts>_create_orderflow_schemas.exs     # all of_* tables in one migration

test/
  showcase/order_flow/
    impl/
      normalize_test.exs
      confidence_decay_test.exs
      alias_promotion_test.exs
    cascade/
      exact_step_test.exs
      fuzzy_trigram_step_test.exs
      client_alias_step_test.exs
      global_alias_step_test.exs
      claude_fallback_step_test.exs
    extraction_test.exs
    client_resolver_test.exs
    pipeline_test.exs
    seed_test.exs
    worker_test.exs
  showcase_web/live/order_flow/
    inbox_live_test.exs
```

**Boundary rules** (per Phase 0 CLAUDE.md):
- Pure functions in `impl/` — no `Repo`, no HTTP, no clock reads. Boundary passes `now` and `repo` via context.
- Cascade `Step` modules pattern-match on `%{repo: ..., now: ..., client_id: ...}` from the context map per the convention documented in `Showcase.Common.CascadeMatcher.Step`.
- `Pipeline` and `Worker` own `Ecto.Multi`, transactions, side effects, AnthropicClient calls, PubSub broadcasts.
- `OrderFlow.MockPrompts` lives in `lib/` but is only called from `test/support` and the `order_flow.ex` context's `register_mock_responses/0` helper. It registers canned responses with `AnthropicClient.Mock`.

---

## Task 1: OrderFlow schemas + migration

**Files:**
- Create: `lib/showcase/order_flow/schemas/client.ex`
- Create: `lib/showcase/order_flow/schemas/product.ex`
- Create: `lib/showcase/order_flow/schemas/product_alias.ex`
- Create: `lib/showcase/order_flow/schemas/order.ex`
- Create: `lib/showcase/order_flow/schemas/order_line.ex`
- Create: `lib/showcase/order_flow/schemas/synthetic_message.ex`
- Create: `priv/repo/migrations/<ts>_create_orderflow_schemas.exs`

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration create_orderflow_schemas
```

Note the timestamp.

- [ ] **Step 2: Write the migration body**

Replace the contents of the new migration file with:

```elixir
defmodule Showcase.Repo.Migrations.CreateOrderflowSchemas do
  use Ecto.Migration

  def change do
    create table(:of_clients) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:of_clients, [:name])

    create table(:of_products) do
      add :sku, :string, null: false
      add :name, :string, null: false
      add :normalized_name, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:of_products, [:sku])
    create index(:of_products, [:normalized_name])

    create table(:of_product_aliases) do
      add :normalized_text, :string, null: false
      add :product_id, references(:of_products, on_delete: :delete_all), null: false
      add :client_id, references(:of_clients, on_delete: :delete_all)  # NULL = global
      add :confidence, :float, null: false, default: 0.5
      add :last_used_at, :utc_datetime_usec, null: false
      add :use_count, :integer, null: false, default: 1
      add :source, :string, null: false  # "correction" | "promotion" | "seed"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_product_aliases, [:normalized_text])
    create index(:of_product_aliases, [:client_id, :normalized_text])
    # gin index for pg_trgm similarity searches on normalized_text
    execute(
      "CREATE INDEX of_product_aliases_text_trgm_idx ON of_product_aliases USING GIN (normalized_text gin_trgm_ops)",
      "DROP INDEX IF EXISTS of_product_aliases_text_trgm_idx"
    )

    create table(:of_synthetic_messages) do
      add :body, :text, null: false
      add :kind, :string, null: false       # "email" | "whatsapp"
      add :scenario, :string, null: false   # matches AnthropicClient.Mock fingerprint+scenario
      add :client_hint, :string             # what the message hints about its sender
      timestamps(type: :utc_datetime_usec)
    end

    create table(:of_orders) do
      add :client_id, references(:of_clients, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending_review"
      add :synthetic_message_id, references(:of_synthetic_messages, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_orders, [:client_id])
    create index(:of_orders, [:status])

    create table(:of_order_lines) do
      add :order_id, references(:of_orders, on_delete: :delete_all), null: false
      add :product_id, references(:of_products, on_delete: :nilify_all)
      add :raw_description, :string, null: false
      add :quantity, :integer, null: false
      add :confidence, :float
      add :match_step, :string  # which cascade step matched ("exact", "fuzzy", etc.)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:of_order_lines, [:order_id])
  end
end
```

- [ ] **Step 3: Write `Client` schema**

Create `lib/showcase/order_flow/schemas/client.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.Client do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_clients" do
    field :name, :string
    field :email, :string
    field :phone, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :email, :phone])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
```

- [ ] **Step 4: Write `Product` schema**

Create `lib/showcase/order_flow/schemas/product.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_products" do
    field :sku, :string
    field :name, :string
    field :normalized_name, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku, :name, :normalized_name])
    |> validate_required([:sku, :name, :normalized_name])
    |> unique_constraint(:sku)
  end
end
```

- [ ] **Step 5: Write `ProductAlias` schema**

Create `lib/showcase/order_flow/schemas/product_alias.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.ProductAlias do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Client, Product}

  schema "of_product_aliases" do
    field :normalized_text, :string
    field :confidence, :float, default: 0.5
    field :last_used_at, :utc_datetime_usec
    field :use_count, :integer, default: 1
    field :source, :string

    belongs_to :product, Product, foreign_key: :product_id
    belongs_to :client, Client, foreign_key: :client_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(alias_struct, attrs) do
    alias_struct
    |> cast(attrs, [:normalized_text, :product_id, :client_id, :confidence,
                    :last_used_at, :use_count, :source])
    |> validate_required([:normalized_text, :product_id, :last_used_at, :source])
    |> validate_inclusion(:source, ["correction", "promotion", "seed"])
  end
end
```

- [ ] **Step 6: Write `Order` and `OrderLine` schemas**

Create `lib/showcase/order_flow/schemas/order.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Client, OrderLine, SyntheticMessage}

  schema "of_orders" do
    field :status, :string, default: "pending_review"

    belongs_to :client, Client, foreign_key: :client_id
    belongs_to :synthetic_message, SyntheticMessage, foreign_key: :synthetic_message_id
    has_many :lines, OrderLine, foreign_key: :order_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:client_id, :status, :synthetic_message_id])
    |> validate_inclusion(:status, ["pending_review", "approved", "rejected"])
  end
end
```

Create `lib/showcase/order_flow/schemas/order_line.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.OrderLine do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.OrderFlow.Schemas.{Order, Product}

  schema "of_order_lines" do
    field :raw_description, :string
    field :quantity, :integer
    field :confidence, :float
    field :match_step, :string

    belongs_to :order, Order, foreign_key: :order_id
    belongs_to :product, Product, foreign_key: :product_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:order_id, :product_id, :raw_description, :quantity,
                    :confidence, :match_step])
    |> validate_required([:order_id, :raw_description, :quantity])
  end
end
```

- [ ] **Step 7: Write `SyntheticMessage` schema**

Create `lib/showcase/order_flow/schemas/synthetic_message.ex`:

```elixir
defmodule Showcase.OrderFlow.Schemas.SyntheticMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_synthetic_messages" do
    field :body, :string
    field :kind, :string
    field :scenario, :string
    field :client_hint, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:body, :kind, :scenario, :client_hint])
    |> validate_required([:body, :kind, :scenario])
    |> validate_inclusion(:kind, ["email", "whatsapp"])
  end
end
```

- [ ] **Step 8: Run migration + verify**

```bash
mix ecto.migrate
mix compile --warnings-as-errors
```

Expected: migration applies cleanly, all schemas compile, no warnings.

Verify tables + index exist:

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d showcase_dev -c "\d of_product_aliases" | head -25
```

Expected: shows the table with all columns + the GIN trigram index.

- [ ] **Step 9: Run full suite — confirm unchanged**

```bash
mix test 2>&1 | tail -3
```

Expected: 1 property + 39 tests, 0 failures (no new tests yet).

- [ ] **Step 10: Commit**

```bash
git add lib/showcase/order_flow/schemas/ priv/repo/migrations/
git commit -m "feat(order_flow): schemas + migration for of_* tables"
```

---

## Task 2: `Normalize` pure module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/impl/normalize.ex`
- Create: `test/showcase/order_flow/impl/normalize_test.exs`

**Contract:** `normalize_text/1` takes a `String.t()` and returns a normalized version: lowercase, trimmed, punctuation stripped, whitespace collapsed. Used to canonicalize product names and message line text for matching.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/impl/normalize_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Impl.NormalizeTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.Normalize

  describe "normalize_text/1" do
    test "lowercases" do
      assert Normalize.normalize_text("HINGES") == "hinges"
    end

    test "trims surrounding whitespace" do
      assert Normalize.normalize_text("  widget   ") == "widget"
    end

    test "collapses internal whitespace" do
      assert Normalize.normalize_text("door     lock") == "door lock"
    end

    test "strips common punctuation" do
      assert Normalize.normalize_text("4mm gaskets!") == "4mm gaskets"
      assert Normalize.normalize_text("widget, large") == "widget large"
      assert Normalize.normalize_text("hinge (heavy duty)") == "hinge heavy duty"
    end

    test "preserves digits and alphanumeric SKU-like tokens" do
      assert Normalize.normalize_text("SKU-00142") == "sku-00142"
      assert Normalize.normalize_text("M8x40") == "m8x40"
    end

    test "empty string returns empty string" do
      assert Normalize.normalize_text("") == ""
    end

    test "nil raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Normalize.normalize_text(nil) end
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/showcase/order_flow/impl/normalize_test.exs
```

Expected: failures — module doesn't exist.

- [ ] **Step 3: Implement `Normalize`**

Create `lib/showcase/order_flow/impl/normalize.ex`:

```elixir
defmodule Showcase.OrderFlow.Impl.Normalize do
  @moduledoc """
  Pure text normalization for matching.

  Steps applied (in order):
    1. lowercase
    2. strip common punctuation (`!`, `,`, `.`, `;`, `:`, `(`, `)`, `?`)
    3. collapse runs of whitespace into a single space
    4. trim surrounding whitespace

  Preserves digits, hyphens (for SKU-like tokens), and other alphanumeric chars.
  """

  @punctuation_pattern ~r/[!,.;:()?]/u

  @spec normalize_text(String.t()) :: String.t()
  def normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(@punctuation_pattern, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/impl/normalize_test.exs
```

Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/impl/normalize.ex test/showcase/order_flow/impl/normalize_test.exs
git commit -m "feat(order_flow): Normalize pure module with TDD"
```

---

## Task 3: `ConfidenceDecay` pure module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/impl/confidence_decay.ex`
- Create: `test/showcase/order_flow/impl/confidence_decay_test.exs`

**Contract:** `decay/3` takes `(raw_confidence, last_used_at, now)` and returns the time-adjusted confidence:
- `< 6 months` since `last_used_at` → `raw_confidence` (no decay)
- `6 to 12 months` → linear ramp from `raw_confidence` down to `0.1`
- `>= 12 months` → `:expired` (caller should filter out)

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/impl/confidence_decay_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Impl.ConfidenceDecayTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.ConfidenceDecay

  @now ~U[2026-06-04 12:00:00.000000Z]

  describe "decay/3" do
    test "recent use (< 6 months) returns raw confidence unchanged" do
      one_month_ago = DateTime.add(@now, -30, :day)
      assert ConfidenceDecay.decay(0.85, one_month_ago, @now) == 0.85
    end

    test "5 months and 29 days returns raw confidence (boundary inside fresh window)" do
      almost_six = DateTime.add(@now, -180 + 1, :day)
      assert ConfidenceDecay.decay(0.85, almost_six, @now) == 0.85
    end

    test "exactly 6 months starts decaying" do
      six_months = DateTime.add(@now, -180, :day)
      decayed = ConfidenceDecay.decay(0.85, six_months, @now)
      assert decayed < 0.85
      assert decayed > 0.1
    end

    test "9 months decays roughly halfway" do
      nine_months = DateTime.add(@now, -270, :day)
      decayed = ConfidenceDecay.decay(0.85, nine_months, @now)
      midpoint = (0.85 + 0.1) / 2
      assert_in_delta decayed, midpoint, 0.02
    end

    test "12 months returns :expired" do
      twelve_months = DateTime.add(@now, -365, :day)
      assert ConfidenceDecay.decay(0.85, twelve_months, @now) == :expired
    end

    test "more than 12 months returns :expired" do
      ancient = DateTime.add(@now, -730, :day)
      assert ConfidenceDecay.decay(0.5, ancient, @now) == :expired
    end

    test "raw_confidence at floor returns floor (until expiry)" do
      one_month_ago = DateTime.add(@now, -30, :day)
      assert ConfidenceDecay.decay(0.1, one_month_ago, @now) == 0.1
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/showcase/order_flow/impl/confidence_decay_test.exs
```

Expected: failures — module doesn't exist.

- [ ] **Step 3: Implement `ConfidenceDecay`**

Create `lib/showcase/order_flow/impl/confidence_decay.ex`:

```elixir
defmodule Showcase.OrderFlow.Impl.ConfidenceDecay do
  @moduledoc """
  Pure time-adjustment of alias confidence.

    * `< 6 months` since `last_used_at` → `raw_confidence` (unchanged).
    * `6 to 12 months` → linear decay from `raw_confidence` to `@floor` (`0.1`).
    * `>= 12 months` → `:expired` (caller filters out).

  Returns a `float() | :expired`. The boundary supplies `now` so this stays pure.
  """

  @floor 0.1
  @fresh_days 180   # 6 months
  @stale_days 365   # 12 months

  @spec decay(float(), DateTime.t(), DateTime.t()) :: float() | :expired
  def decay(raw_confidence, %DateTime{} = last_used_at, %DateTime{} = now)
      when is_float(raw_confidence) do
    days = DateTime.diff(now, last_used_at, :second) / 86_400.0

    cond do
      days < @fresh_days -> raw_confidence
      days >= @stale_days -> :expired
      true ->
        # linear interpolation from raw_confidence at day 180 to @floor at day 365
        progress = (days - @fresh_days) / (@stale_days - @fresh_days)
        raw_confidence - progress * (raw_confidence - @floor)
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/impl/confidence_decay_test.exs
```

Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/impl/confidence_decay.ex test/showcase/order_flow/impl/confidence_decay_test.exs
git commit -m "feat(order_flow): ConfidenceDecay pure module with TDD"
```

---

## Task 4: `AliasPromotion` pure module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/impl/alias_promotion.ex`
- Create: `test/showcase/order_flow/impl/alias_promotion_test.exs`

**Contract:** `eligible_for_global?/1` takes a list of `%{client_id: integer(), confidence: float()}` maps (rows representing existing client-scoped aliases for a given `normalized_text → product_id` mapping) and returns `true` if ≥2 distinct clients have it AND average confidence ≥ `0.7`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/impl/alias_promotion_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Impl.AliasPromotionTest do
  use ExUnit.Case, async: true

  alias Showcase.OrderFlow.Impl.AliasPromotion

  describe "eligible_for_global?/1" do
    test "false when zero matches" do
      refute AliasPromotion.eligible_for_global?([])
    end

    test "false when only one client uses the alias" do
      refute AliasPromotion.eligible_for_global?([%{client_id: 1, confidence: 0.95}])
    end

    test "false when 2+ clients but average confidence < 0.7" do
      refute AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.6},
        %{client_id: 2, confidence: 0.55}
      ])
    end

    test "true when 2 distinct clients and avg confidence >= 0.7" do
      assert AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.85},
        %{client_id: 2, confidence: 0.75}
      ])
    end

    test "false when 2 entries are from same client" do
      refute AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.9},
        %{client_id: 1, confidence: 0.9}
      ])
    end

    test "true when 3+ clients drag avg confidence up despite one weak entry" do
      assert AliasPromotion.eligible_for_global?([
        %{client_id: 1, confidence: 0.9},
        %{client_id: 2, confidence: 0.9},
        %{client_id: 3, confidence: 0.4}
      ])
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/showcase/order_flow/impl/alias_promotion_test.exs
```

- [ ] **Step 3: Implement `AliasPromotion`**

Create `lib/showcase/order_flow/impl/alias_promotion.ex`:

```elixir
defmodule Showcase.OrderFlow.Impl.AliasPromotion do
  @moduledoc """
  Pure logic for deciding when a client-scoped product alias should be
  promoted to a global alias.

  Rule (per spec §4.1): a `normalized_text → product_id` mapping is eligible
  for global promotion once at least 2 distinct clients have written it AND
  the mean confidence across all entries is ≥ 0.7.
  """

  @min_distinct_clients 2
  @min_avg_confidence 0.7

  @type alias_row :: %{client_id: integer(), confidence: float()}

  @spec eligible_for_global?(list(alias_row())) :: boolean()
  def eligible_for_global?(entries) when is_list(entries) do
    distinct = entries |> Enum.map(& &1.client_id) |> Enum.uniq() |> length()

    if distinct < @min_distinct_clients do
      false
    else
      avg = entries |> Enum.map(& &1.confidence) |> mean()
      avg >= @min_avg_confidence
    end
  end

  defp mean([]), do: 0.0
  defp mean(xs) when is_list(xs), do: Enum.sum(xs) / length(xs)
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/impl/alias_promotion_test.exs
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/impl/alias_promotion.ex test/showcase/order_flow/impl/alias_promotion_test.exs
git commit -m "feat(order_flow): AliasPromotion pure module with TDD"
```

---

## Task 5: `ExactStep` cascade module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/cascade/exact_step.ex`
- Create: `test/showcase/order_flow/cascade/exact_step_test.exs`

**Contract:** Implements `Showcase.Common.CascadeMatcher.Step`. Given a raw description string + context `%{repo: ..., now: ..., client_id: ...}`, looks up `Product` by `normalized_name == Normalize.normalize_text(input)`. Returns `{:match, product, 1.0}` if found, `:no_match` otherwise.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/cascade/exact_step_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Cascade.ExactStepTest do
  use Showcase.DataCase, async: true

  alias Showcase.OrderFlow.Cascade.ExactStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, %{widget: widget}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "returns 1.0 match when normalized input equals product normalized_name", %{widget: widget} do
    assert {:match, found, 1.0} = ExactStep.try_match("Widget", ctx())
    assert found.id == widget.id
  end

  test "matches after Normalize trims and lowercases", %{widget: widget} do
    assert {:match, found, 1.0} = ExactStep.try_match("  WIDGET  ", ctx())
    assert found.id == widget.id
  end

  test "no_match when product doesn't exist" do
    assert ExactStep.try_match("nonexistent", ctx()) == :no_match
  end

  test "name/0 returns :exact" do
    assert ExactStep.name() == :exact
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/cascade/exact_step_test.exs
```

Expected: failures — module doesn't exist.

- [ ] **Step 3: Implement `ExactStep`**

Create `lib/showcase/order_flow/cascade/exact_step.ex`:

```elixir
defmodule Showcase.OrderFlow.Cascade.ExactStep do
  @moduledoc """
  First step in the OrderFlow product-matching cascade.

  Looks up `Product` by `normalized_name == Normalize.normalize_text(input)`.
  Returns a 1.0 confidence match on hit, `:no_match` otherwise.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.Normalize
  alias Showcase.OrderFlow.Schemas.Product

  @impl true
  def name, do: :exact

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    case repo.one(from p in Product, where: p.normalized_name == ^normalized) do
      nil -> :no_match
      %Product{} = product -> {:match, product, 1.0}
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/cascade/exact_step_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/cascade/exact_step.ex test/showcase/order_flow/cascade/exact_step_test.exs
git commit -m "feat(order_flow): ExactStep cascade matcher with TDD"
```

---

## Task 6: `FuzzyTrigramStep` cascade module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/cascade/fuzzy_trigram_step.ex`
- Create: `test/showcase/order_flow/cascade/fuzzy_trigram_step_test.exs`

**Contract:** Uses Postgres `pg_trgm` similarity to find the closest `Product.normalized_name`. Returns `{:match, product, similarity}` if `similarity >= 0.5`, else `:no_match`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/cascade/fuzzy_trigram_step_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Cascade.FuzzyTrigramStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.FuzzyTrigramStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    {:ok, hinges} =
      %Product{}
      |> Product.changeset(%{sku: "HNG-001", name: "Hinges", normalized_name: "hinges"})
      |> Repo.insert()

    {:ok, %{hinges: hinges}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "near-spelling match returns product with similarity >= 0.5", %{hinges: hinges} do
    {:match, found, score} = FuzzyTrigramStep.try_match("hings", ctx())
    assert found.id == hinges.id
    assert score >= 0.5
    assert score < 1.0
  end

  test "exact match returns score 1.0", %{hinges: hinges} do
    {:match, found, score} = FuzzyTrigramStep.try_match("hinges", ctx())
    assert found.id == hinges.id
    assert score == 1.0
  end

  test "completely unrelated input returns no_match" do
    assert FuzzyTrigramStep.try_match("zzzzzzz", ctx()) == :no_match
  end

  test "name/0 returns :fuzzy_trigram" do
    assert FuzzyTrigramStep.name() == :fuzzy_trigram
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/cascade/fuzzy_trigram_step_test.exs
```

- [ ] **Step 3: Implement `FuzzyTrigramStep`**

Create `lib/showcase/order_flow/cascade/fuzzy_trigram_step.ex`:

```elixir
defmodule Showcase.OrderFlow.Cascade.FuzzyTrigramStep do
  @moduledoc """
  Second step in the OrderFlow cascade.

  Uses Postgres `pg_trgm` similarity (extension enabled in Phase 0) to find
  the closest `Product.normalized_name` to the input. Returns the highest
  similarity if it meets the threshold.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.Normalize
  alias Showcase.OrderFlow.Schemas.Product

  @similarity_threshold 0.5

  @impl true
  def name, do: :fuzzy_trigram

  @impl true
  def try_match(input, %{repo: repo}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from p in Product,
        select: {p, fragment("similarity(?, ?)", p.normalized_name, ^normalized)},
        order_by: [desc: fragment("similarity(?, ?)", p.normalized_name, ^normalized)],
        limit: 1

    case repo.one(query) do
      nil -> :no_match
      {%Product{} = product, score} when score >= @similarity_threshold ->
        {:match, product, score}
      _ -> :no_match
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/cascade/fuzzy_trigram_step_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/cascade/fuzzy_trigram_step.ex test/showcase/order_flow/cascade/fuzzy_trigram_step_test.exs
git commit -m "feat(order_flow): FuzzyTrigramStep using pg_trgm with TDD"
```

---

## Task 7: `ClientAliasStep` cascade module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/cascade/client_alias_step.ex`
- Create: `test/showcase/order_flow/cascade/client_alias_step_test.exs`

**Contract:** Looks up `ProductAlias` rows where `client_id == context.client_id AND normalized_text == Normalize.normalize_text(input)`. Filters out expired entries via `ConfidenceDecay`. Returns the freshest match with its decayed confidence.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/cascade/client_alias_step_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Cascade.ClientAliasStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.ClientAliasStep
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias}
  alias Showcase.Repo

  @now ~U[2026-06-04 12:00:00.000000Z]

  setup do
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})
    {:ok, gasket} =
      %Product{}
      |> Product.changeset(%{sku: "GSK-4MM", name: "4mm Gasket", normalized_name: "4mm gasket"})
      |> Repo.insert()

    {:ok, %{client: client, gasket: gasket}}
  end

  defp ctx(client_id),
    do: %{repo: Repo, now: @now, client_id: client_id}

  test "returns match when client-scoped alias exists and is fresh",
       %{client: client, gasket: gasket} do
    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: one_month_ago,
        source: "correction"
      })
      |> Repo.insert()

    {:match, found, score} = ClientAliasStep.try_match("The 4mm Gaskets", ctx(client.id))
    assert found.id == gasket.id
    assert score == 0.85
  end

  test "ignores aliases from other clients",
       %{client: client, gasket: gasket} do
    {:ok, other} = Repo.insert(%Client{name: "Beta Corp"})
    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: other.id,
        confidence: 0.85,
        last_used_at: one_month_ago,
        source: "correction"
      })
      |> Repo.insert()

    assert ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id)) == :no_match
  end

  test "filters out expired aliases",
       %{client: client, gasket: gasket} do
    over_a_year_ago = DateTime.add(@now, -400, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: over_a_year_ago,
        source: "correction"
      })
      |> Repo.insert()

    assert ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id)) == :no_match
  end

  test "decays confidence between 6 and 12 months",
       %{client: client, gasket: gasket} do
    nine_months_ago = DateTime.add(@now, -270, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: client.id,
        confidence: 0.85,
        last_used_at: nine_months_ago,
        source: "correction"
      })
      |> Repo.insert()

    {:match, _found, decayed} = ClientAliasStep.try_match("the 4mm gaskets", ctx(client.id))
    assert decayed < 0.85
    assert decayed > 0.1
  end

  test "no_match when client_id is nil" do
    assert ClientAliasStep.try_match("anything", %{repo: Repo, now: @now, client_id: nil}) ==
             :no_match
  end

  test "name/0 returns :client_alias" do
    assert ClientAliasStep.name() == :client_alias
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/cascade/client_alias_step_test.exs
```

- [ ] **Step 3: Implement `ClientAliasStep`**

Create `lib/showcase/order_flow/cascade/client_alias_step.ex`:

```elixir
defmodule Showcase.OrderFlow.Cascade.ClientAliasStep do
  @moduledoc """
  Third step in the OrderFlow cascade.

  Looks up `ProductAlias` rows scoped to the current `client_id` matching the
  normalized input. Applies time-based confidence decay; filters out expired
  entries. Returns the freshest match (highest `last_used_at`) with its
  decayed confidence.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.{ConfidenceDecay, Normalize}
  alias Showcase.OrderFlow.Schemas.ProductAlias

  @impl true
  def name, do: :client_alias

  @impl true
  def try_match(_input, %{client_id: nil}), do: :no_match

  @impl true
  def try_match(input, %{repo: repo, now: now, client_id: client_id}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from a in ProductAlias,
        where: a.client_id == ^client_id and a.normalized_text == ^normalized,
        order_by: [desc: a.last_used_at],
        preload: [:product]

    case repo.all(query) do
      [] ->
        :no_match

      aliases ->
        aliases
        |> Enum.map(&{&1, ConfidenceDecay.decay(&1.confidence, &1.last_used_at, now)})
        |> Enum.reject(fn {_a, c} -> c == :expired end)
        |> case do
          [] -> :no_match
          [{alias_row, decayed_confidence} | _] -> {:match, alias_row.product, decayed_confidence}
        end
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/cascade/client_alias_step_test.exs
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/cascade/client_alias_step.ex test/showcase/order_flow/cascade/client_alias_step_test.exs
git commit -m "feat(order_flow): ClientAliasStep cascade with decay + TDD"
```

---

## Task 8: `GlobalAliasStep` cascade module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/cascade/global_alias_step.ex`
- Create: `test/showcase/order_flow/cascade/global_alias_step_test.exs`

**Contract:** Same shape as `ClientAliasStep` but queries `client_id IS NULL` (the global pool). No client_id constraint needed. Filters expired entries via `ConfidenceDecay`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/cascade/global_alias_step_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Cascade.GlobalAliasStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.GlobalAliasStep
  alias Showcase.OrderFlow.Schemas.{Product, ProductAlias}
  alias Showcase.Repo

  @now ~U[2026-06-04 12:00:00.000000Z]

  setup do
    {:ok, gasket} =
      %Product{}
      |> Product.changeset(%{sku: "GSK-4MM", name: "4mm Gasket", normalized_name: "4mm gasket"})
      |> Repo.insert()

    one_month_ago = DateTime.add(@now, -30, :day)

    {:ok, _} =
      %ProductAlias{}
      |> ProductAlias.changeset(%{
        normalized_text: "the 4mm gaskets",
        product_id: gasket.id,
        client_id: nil,
        confidence: 0.78,
        last_used_at: one_month_ago,
        source: "promotion"
      })
      |> Repo.insert()

    {:ok, %{gasket: gasket}}
  end

  defp ctx, do: %{repo: Repo, now: @now, client_id: nil}

  test "returns match when fresh global alias exists", %{gasket: gasket} do
    {:match, found, score} = GlobalAliasStep.try_match("The 4mm Gaskets", ctx())
    assert found.id == gasket.id
    assert score == 0.78
  end

  test "matches even when client_id is supplied in context", %{gasket: gasket} do
    # Global aliases should be tried regardless of client_id in context
    ctx_with_client = %{ctx() | client_id: 42}
    {:match, found, _score} = GlobalAliasStep.try_match("the 4mm gaskets", ctx_with_client)
    assert found.id == gasket.id
  end

  test "no_match when nothing in global pool" do
    Repo.delete_all(ProductAlias)
    assert GlobalAliasStep.try_match("anything", ctx()) == :no_match
  end

  test "name/0 returns :global_alias" do
    assert GlobalAliasStep.name() == :global_alias
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/cascade/global_alias_step_test.exs
```

- [ ] **Step 3: Implement `GlobalAliasStep`**

Create `lib/showcase/order_flow/cascade/global_alias_step.ex`:

```elixir
defmodule Showcase.OrderFlow.Cascade.GlobalAliasStep do
  @moduledoc """
  Fourth step in the OrderFlow cascade.

  Queries the **global** alias pool (`client_id IS NULL`). Same decay rules
  as `ClientAliasStep`. Runs regardless of the request's client_id.
  """

  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.OrderFlow.Impl.{ConfidenceDecay, Normalize}
  alias Showcase.OrderFlow.Schemas.ProductAlias

  @impl true
  def name, do: :global_alias

  @impl true
  def try_match(input, %{repo: repo, now: now}) when is_binary(input) do
    normalized = Normalize.normalize_text(input)

    query =
      from a in ProductAlias,
        where: is_nil(a.client_id) and a.normalized_text == ^normalized,
        order_by: [desc: a.last_used_at],
        preload: [:product]

    case repo.all(query) do
      [] ->
        :no_match

      aliases ->
        aliases
        |> Enum.map(&{&1, ConfidenceDecay.decay(&1.confidence, &1.last_used_at, now)})
        |> Enum.reject(fn {_a, c} -> c == :expired end)
        |> case do
          [] -> :no_match
          [{alias_row, decayed_confidence} | _] -> {:match, alias_row.product, decayed_confidence}
        end
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/cascade/global_alias_step_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/cascade/global_alias_step.ex test/showcase/order_flow/cascade/global_alias_step_test.exs
git commit -m "feat(order_flow): GlobalAliasStep cascade with TDD"
```

---

## Task 9: `ClaudeFallbackStep` cascade module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/cascade/claude_fallback_step.ex`
- Create: `test/showcase/order_flow/cascade/claude_fallback_step_test.exs`

**Contract:** Last resort. Calls `AnthropicClient` (Mock in tests) with the input description + a catalog summary in the system prompt. Expects Claude to return `{"sku": "...", "confidence": 0.0-1.0}`. Parses via `ResilientJSONParser`. Returns `{:match, product, claude_confidence}` if SKU is found in DB, else `:no_match`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/cascade/claude_fallback_step_test.exs`:

```elixir
defmodule Showcase.OrderFlow.Cascade.ClaudeFallbackStepTest do
  use Showcase.DataCase, async: true

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Cascade.ClaudeFallbackStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, %{widget: widget}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "returns match when Claude responds with a known SKU", %{widget: widget} do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "the gizmo thing",
      text: ~s({"sku": "WGT-001", "confidence": 0.72})
    )

    {:match, found, score} = ClaudeFallbackStep.try_match("the gizmo thing", ctx())
    assert found.id == widget.id
    assert score == 0.72
  end

  test "no_match when Claude returns a SKU not in the DB" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "unknown thing",
      text: ~s({"sku": "GHOST-999", "confidence": 0.9})
    )

    assert ClaudeFallbackStep.try_match("unknown thing", ctx()) == :no_match
  end

  test "no_match when Claude returns malformed JSON" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "bad json",
      text: "not json at all"
    )

    assert ClaudeFallbackStep.try_match("bad json", ctx()) == :no_match
  end

  test "salvages a truncated JSON response with :partial flag" do
    Mock.register(
      "order_flow:claude_fallback:v1",
      scenario: "truncated",
      text: ~s({"sku": "WGT-001", "confidence": 0.5)
    )

    # ResilientJSONParser should salvage; we still match the product.
    {:match, _found, score} = ClaudeFallbackStep.try_match("truncated", ctx())
    assert score == 0.5
  end

  test "no_match when AnthropicClient returns an error" do
    # No Mock.register — unregistered call returns {:error, {:no_mock, _, _}}
    assert ClaudeFallbackStep.try_match("no mock registered", ctx()) == :no_match
  end

  test "name/0 returns :claude_fallback" do
    assert ClaudeFallbackStep.name() == :claude_fallback
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/cascade/claude_fallback_step_test.exs
```

- [ ] **Step 3: Implement `ClaudeFallbackStep`**

Create `lib/showcase/order_flow/cascade/claude_fallback_step.ex`:

```elixir
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
      system: "You are a product matcher. Respond with JSON: {\"sku\": \"...\", \"confidence\": 0.0-1.0}.",
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
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/cascade/claude_fallback_step_test.exs
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/cascade/claude_fallback_step.ex test/showcase/order_flow/cascade/claude_fallback_step_test.exs
git commit -m "feat(order_flow): ClaudeFallbackStep cascade with mock-driven TDD"
```

---

## Task 10: `Extraction` boundary module (TDD)

**Files:**
- Create: `lib/showcase/order_flow/extraction.ex`
- Create: `test/showcase/order_flow/extraction_test.exs`

**Contract:** `extract/1` takes a message body (binary), calls `AnthropicClient` with the extraction system prompt, parses the response into `{:ok, %{client_hint: String.t(), lines: [%{description: String.t(), quantity: integer()}]}}` or `{:error, reason}`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/extraction_test.exs`:

```elixir
defmodule Showcase.OrderFlow.ExtractionTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Extraction

  setup do
    Mock.reset()
    :ok
  end

  test "extracts client hint + lines from a clean message" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "hinges_and_locks",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "hinges", "quantity": 200}, {"description": "door locks", "quantity": 50}]})
    )

    assert {:ok, result} = Extraction.extract("hi, 200 hinges and 50 door locks", scenario: "hinges_and_locks")
    assert result.client_hint == "Acme Inc"
    assert length(result.lines) == 2
    assert Enum.at(result.lines, 0) == %{description: "hinges", quantity: 200}
  end

  test "returns error when Claude returns malformed json" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "garbage",
      text: "not json"
    )

    assert {:error, _} = Extraction.extract("anything", scenario: "garbage")
  end

  test "returns error when AnthropicClient fails" do
    # Unregistered scenario triggers no_mock
    assert {:error, _} = Extraction.extract("anything", scenario: "unregistered")
  end

  test "salvages a partial JSON response with whatever lines parsed" do
    Mock.register(
      "order_flow:extract:v1",
      scenario: "truncated",
      text: ~s({"client_hint": "Acme", "lines": [{"description": "widget", "quantity": 5}, {"description": "gadg)
    )

    {:ok, result} = Extraction.extract("body doesn't matter", scenario: "truncated")
    assert result.client_hint == "Acme"
    assert length(result.lines) == 1
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/extraction_test.exs
```

- [ ] **Step 3: Implement `Extraction`**

Create `lib/showcase/order_flow/extraction.ex`:

```elixir
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
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/extraction_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/extraction.ex test/showcase/order_flow/extraction_test.exs
git commit -m "feat(order_flow): Extraction boundary with mock-driven TDD"
```

---

## Task 11: `ClientResolver` boundary (TDD)

**Files:**
- Create: `lib/showcase/order_flow/client_resolver.ex`
- Create: `test/showcase/order_flow/client_resolver_test.exs`

**Contract:** `resolve/2` takes `(client_hint :: String.t() | nil, repo)` and returns:
- `{:ok, client}` — exact name match found
- `{:needs_human, reason}` — no match or ambiguous

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/client_resolver_test.exs`:

```elixir
defmodule Showcase.OrderFlow.ClientResolverTest do
  use Showcase.DataCase, async: true

  alias Showcase.OrderFlow.ClientResolver
  alias Showcase.OrderFlow.Schemas.Client
  alias Showcase.Repo

  setup do
    {:ok, acme} = Repo.insert(%Client{name: "Acme Inc", email: "acme@example.com"})
    {:ok, %{acme: acme}}
  end

  test "exact name match returns client", %{acme: acme} do
    assert {:ok, found} = ClientResolver.resolve("Acme Inc", Repo)
    assert found.id == acme.id
  end

  test "case-insensitive name match" do
    assert {:ok, _} = ClientResolver.resolve("acme inc", Repo)
  end

  test "no match returns needs_human" do
    assert {:needs_human, _reason} = ClientResolver.resolve("Unknown Co", Repo)
  end

  test "nil hint returns needs_human" do
    assert {:needs_human, _reason} = ClientResolver.resolve(nil, Repo)
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/client_resolver_test.exs
```

- [ ] **Step 3: Implement `ClientResolver`**

Create `lib/showcase/order_flow/client_resolver.ex`:

```elixir
defmodule Showcase.OrderFlow.ClientResolver do
  @moduledoc """
  Maps a `client_hint` (free-text name extracted from the message) to a
  Client row. Returns `{:ok, client}` on case-insensitive name match,
  `{:needs_human, reason}` otherwise.
  """

  import Ecto.Query

  alias Showcase.OrderFlow.Schemas.Client

  @spec resolve(String.t() | nil, Ecto.Repo.t()) ::
          {:ok, Client.t()} | {:needs_human, String.t()}
  def resolve(nil, _repo), do: {:needs_human, "no client hint in message"}

  def resolve(hint, repo) when is_binary(hint) do
    normalized = String.downcase(String.trim(hint))

    case repo.one(from c in Client, where: fragment("lower(?)", c.name) == ^normalized) do
      nil -> {:needs_human, "no matching client for hint: #{inspect(hint)}"}
      %Client{} = client -> {:ok, client}
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/client_resolver_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/client_resolver.ex test/showcase/order_flow/client_resolver_test.exs
git commit -m "feat(order_flow): ClientResolver boundary with TDD"
```

---

## Task 12: `Pipeline` orchestration boundary (TDD)

**Files:**
- Create: `lib/showcase/order_flow/pipeline.ex`
- Create: `test/showcase/order_flow/pipeline_test.exs`

**Contract:** `process_message/2` takes a `%SyntheticMessage{}` + a context map (carries `now`). Runs the full pipeline:
1. Call `Extraction.extract/2` → get `client_hint + lines`
2. Call `ClientResolver.resolve/2` → get `client_id` or escalate
3. For each line: run the 5-step cascade via `CascadeMatcher.run/3` with context `%{repo, now, client_id}`
4. Insert `Order` + `OrderLine` rows via `Ecto.Multi`
5. Broadcast progress on `"order_flow:processing:#{message_id}"` PubSub topic at each meaningful step

Returns `{:ok, order}` or `{:error, reason}`.

- [ ] **Step 1: Write failing test**

Create `test/showcase/order_flow/pipeline_test.exs`:

```elixir
defmodule Showcase.OrderFlow.PipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.{Client, Order, OrderLine, Product, SyntheticMessage}
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, gadget} =
      %Product{}
      |> Product.changeset(%{sku: "GDG-001", name: "Gadget", normalized_name: "gadget"})
      |> Repo.insert()

    {:ok, msg} =
      %SyntheticMessage{}
      |> SyntheticMessage.changeset(%{
        body: "200 widgets and 50 gadgets",
        kind: "email",
        scenario: "widgets_gadgets",
        client_hint: "Acme Inc"
      })
      |> Repo.insert()

    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widgets", "quantity": 200}, {"description": "gadgets", "quantity": 50}]})
    )

    {:ok, %{client: client, widget: widget, gadget: gadget, message: msg}}
  end

  defp ctx, do: %{now: DateTime.utc_now()}

  test "creates an Order with matched lines for a clean happy path",
       %{message: msg, client: client, widget: widget, gadget: gadget} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "order_flow:processing:#{msg.id}")

    {:ok, order} = Pipeline.process_message(msg, ctx())

    assert order.client_id == client.id
    assert order.status == "pending_review"

    lines = Repo.preload(order, :lines).lines |> Enum.sort_by(& &1.quantity, :desc)
    assert length(lines) == 2

    [widgets, gadgets] = lines
    assert widgets.product_id == widget.id
    assert widgets.quantity == 200
    assert widgets.match_step == "exact"

    assert gadgets.product_id == gadget.id
    assert gadgets.quantity == 50
    assert gadgets.match_step == "exact"

    # PubSub broadcasts received
    assert_received {:order_flow, :extracted, _}
    assert_received {:order_flow, :client_identified, _}
    # one :line_matched per line
    assert_received {:order_flow, :line_matched, %{step: :exact}}
    assert_received {:order_flow, :line_matched, %{step: :exact}}
    assert_received {:order_flow, :order_created, %{order_id: _}}
  end

  test "returns error when client_hint can't be resolved",
       %{message: msg} do
    Mock.reset()
    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Unknown Co", "lines": [{"description": "widget", "quantity": 1}]})
    )

    {:error, {:client_unresolved, _}} = Pipeline.process_message(msg, ctx())
  end

  test "creates order line with nil product_id when no cascade step matches",
       %{message: msg} do
    Mock.reset()
    Mock.register(
      "order_flow:extract:v1",
      scenario: "widgets_gadgets",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "mystery item", "quantity": 1}]})
    )

    {:ok, order} = Pipeline.process_message(msg, ctx())
    lines = Repo.preload(order, :lines).lines

    assert length(lines) == 1
    assert hd(lines).product_id == nil
    assert hd(lines).match_step == nil
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/pipeline_test.exs
```

- [ ] **Step 3: Implement `Pipeline`**

Create `lib/showcase/order_flow/pipeline.ex`:

```elixir
defmodule Showcase.OrderFlow.Pipeline do
  @moduledoc """
  Boundary that orchestrates the OrderFlow pipeline.

  Stages (each broadcasts PubSub on `order_flow:processing:<message_id>`):
    1. :extracted          — Claude returned {client_hint, lines}
    2. :client_identified  — client_hint resolved to a Client row
    3. :line_matched (×N)  — per line, one of the cascade steps matched (or all failed)
    4. :order_created      — Order + OrderLines inserted

  Returns `{:ok, %Order{}}` on success, `{:error, reason}` otherwise.
  """

  alias Ecto.Multi
  alias Showcase.Common.CascadeMatcher
  alias Showcase.OrderFlow.{ClientResolver, Extraction}
  alias Showcase.OrderFlow.Cascade.{
    ClaudeFallbackStep,
    ClientAliasStep,
    ExactStep,
    FuzzyTrigramStep,
    GlobalAliasStep
  }
  alias Showcase.OrderFlow.Schemas.{Order, OrderLine, SyntheticMessage}
  alias Showcase.Repo

  @cascade_steps [
    ExactStep,
    FuzzyTrigramStep,
    ClientAliasStep,
    GlobalAliasStep,
    ClaudeFallbackStep
  ]

  @spec process_message(SyntheticMessage.t(), %{now: DateTime.t()}) ::
          {:ok, Order.t()} | {:error, term()}
  def process_message(%SyntheticMessage{} = msg, %{now: now}) do
    topic = "order_flow:processing:#{msg.id}"

    with {:ok, extracted} <- Extraction.extract(msg.body, scenario: msg.scenario),
         _ = broadcast(topic, :extracted, %{client_hint: extracted.client_hint, line_count: length(extracted.lines)}),
         {:ok, client} <- resolve_client(extracted.client_hint, topic) do
      matched_lines =
        Enum.map(extracted.lines, fn line ->
          context = %{repo: Repo, now: now, client_id: client.id}
          outcome = CascadeMatcher.run(@cascade_steps, line.description, context)

          attrs = %{
            raw_description: line.description,
            quantity: line.quantity,
            product_id: if(outcome.matched, do: outcome.value.id),
            confidence: outcome.confidence,
            match_step: if(outcome.step, do: to_string(outcome.step))
          }

          broadcast(topic, :line_matched, %{
            description: line.description,
            step: outcome.step,
            confidence: outcome.confidence,
            matched: outcome.matched
          })

          attrs
        end)

      multi =
        Multi.new()
        |> Multi.insert(:order, Order.changeset(%Order{}, %{
          client_id: client.id,
          status: "pending_review",
          synthetic_message_id: msg.id
        }))
        |> Multi.run(:lines, fn _repo, %{order: order} ->
          insert_lines(order, matched_lines)
        end)

      case Repo.transaction(multi) do
        {:ok, %{order: order}} ->
          broadcast(topic, :order_created, %{order_id: order.id})
          {:ok, order}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    else
      {:needs_human, reason} -> {:error, {:client_unresolved, reason}}
      {:error, _} = err -> err
    end
  end

  defp resolve_client(hint, topic) do
    case ClientResolver.resolve(hint, Repo) do
      {:ok, client} ->
        broadcast(topic, :client_identified, %{client_id: client.id, name: client.name})
        {:ok, client}

      {:needs_human, reason} = err ->
        broadcast(topic, :client_unresolved, %{reason: reason})
        err
    end
  end

  defp insert_lines(order, line_attrs) do
    results =
      Enum.map(line_attrs, fn attrs ->
        %OrderLine{}
        |> OrderLine.changeset(Map.put(attrs, :order_id, order.id))
        |> Repo.insert()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, line} -> line end)}
      {:error, _} = err -> err
    end
  end

  defp broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, topic, {:order_flow, event, payload})
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/pipeline_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/pipeline.ex test/showcase/order_flow/pipeline_test.exs
git commit -m "feat(order_flow): Pipeline orchestration with PubSub stage broadcasts"
```

---

## Task 13: Oban `Worker` for OrderFlow (TDD)

**Files:**
- Create: `lib/showcase/order_flow/worker.ex`
- Create: `test/showcase/order_flow/worker_test.exs`

**Contract:** Oban worker on `:order_flow` queue. Performs `process/1` given `%{"message_id" => id}` — fetches the message, calls `Pipeline.process_message/2`, returns `:ok` or `{:error, reason}`.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/worker_test.exs`:

```elixir
defmodule Showcase.OrderFlow.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Schemas.{Client, Product, SyntheticMessage}
  alias Showcase.OrderFlow.Worker
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, _} = Repo.insert(%Client{name: "Acme Inc"})
    {:ok, _} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, msg} =
      %SyntheticMessage{}
      |> SyntheticMessage.changeset(%{
        body: "1 widget please",
        kind: "email",
        scenario: "one_widget",
        client_hint: "Acme Inc"
      })
      |> Repo.insert()

    Mock.register(
      "order_flow:extract:v1",
      scenario: "one_widget",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widget", "quantity": 1}]})
    )

    {:ok, %{message: msg}}
  end

  test "perform/1 processes the message and returns :ok", %{message: msg} do
    assert :ok = perform_job(Worker, %{"message_id" => msg.id})
  end

  test "perform/1 returns {:error, _} for an unknown message id" do
    assert {:error, :not_found} = perform_job(Worker, %{"message_id" => 999_999})
  end

  test "Worker is configured on :order_flow queue" do
    assert Worker.__opts__()[:queue] == :order_flow
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/worker_test.exs
```

- [ ] **Step 3: Implement `Worker`**

Create `lib/showcase/order_flow/worker.ex`:

```elixir
defmodule Showcase.OrderFlow.Worker do
  @moduledoc """
  Oban worker that processes a SyntheticMessage through the OrderFlow pipeline.

  Enqueued by `Showcase.OrderFlow.enqueue/1` (the public context). Runs on the
  `:order_flow` queue configured in `config/config.exs` since Phase 0.
  """

  use Oban.Worker, queue: :order_flow, max_attempts: 3

  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.SyntheticMessage
  alias Showcase.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    case Repo.get(SyntheticMessage, message_id) do
      nil ->
        {:error, :not_found}

      %SyntheticMessage{} = msg ->
        case Pipeline.process_message(msg, %{now: DateTime.utc_now()}) do
          {:ok, _order} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/worker_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/worker.ex test/showcase/order_flow/worker_test.exs
git commit -m "feat(order_flow): Oban worker on :order_flow queue with TDD"
```

---

## Task 14: `OrderFlow` public context + `MockPrompts` registration

**Files:**
- Create: `lib/showcase/order_flow.ex`
- Create: `lib/showcase/order_flow/mock_prompts.ex`

**Contract:**
- `OrderFlow.enqueue_random/0` — picks an unprocessed message, enqueues `Worker`. Returns `{:ok, %Oban.Job{}, %SyntheticMessage{}}` or `{:error, :no_messages}`.
- `OrderFlow.list_messages/0` — for the LiveView inbox.
- `OrderFlow.list_orders/0` — for the LiveView order list.
- `OrderFlow.find_order/1` — for the result view.
- `OrderFlow.register_mock_responses/0` — called from test setup to load all scenarios at once.
- `MockPrompts.scenarios/0` — returns the bundle of `(scenario_name, extract_text, fallback_text)` records used by both the seed and the mock-response registration.

- [ ] **Step 1: Implement `MockPrompts`**

Create `lib/showcase/order_flow/mock_prompts.ex`:

```elixir
defmodule Showcase.OrderFlow.MockPrompts do
  @moduledoc """
  The bundle of (scenario_name, extract_text, fallback_text_or_nil) used by
  both the seed (to plant SyntheticMessages with matching scenarios) and the
  test-time Mock registration.

  Keeping these in one module guarantees the two never drift apart — adding a
  new demo scenario means editing this one file.
  """

  @scenarios [
    %{
      name: "hinges_and_locks",
      kind: "email",
      client_hint: "Acme Inc",
      body: "Hi, I need 200 hinges and 50 door locks for the warehouse — same as last month. Thanks!",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "hinges", "quantity": 200}, {"description": "door locks", "quantity": 50}]}),
      fallback_responses: []
    },
    %{
      name: "gaskets_alias",
      kind: "whatsapp",
      client_hint: "Beta Industries",
      body: "10 boxes of the 4mm gaskets we always order",
      extract_response: ~s({"client_hint": "Beta Industries", "lines": [{"description": "the 4mm gaskets we always order", "quantity": 10}]}),
      # ClaudeFallbackStep won't be called if a client-scoped alias exists (seeded)
      fallback_responses: []
    },
    %{
      name: "mixed_known_unknown",
      kind: "email",
      client_hint: "Acme Inc",
      body: "Send 12 widgets and 3 of those gizmo things",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widgets", "quantity": 12}, {"description": "those gizmo things", "quantity": 3}]}),
      fallback_responses: [
        %{scenario: "those gizmo things", text: ~s({"sku": "GDG-001", "confidence": 0.65})}
      ]
    },
    %{
      name: "low_confidence_mystery",
      kind: "whatsapp",
      client_hint: "Acme Inc",
      body: "some of those things we ordered last time",
      extract_response: ~s({"client_hint": "Acme Inc", "lines": [{"description": "some of those things we ordered last time", "quantity": 1}]}),
      fallback_responses: [
        %{scenario: "some of those things we ordered last time", text: ~s({"sku": "GHOST-999", "confidence": 0.2})}
      ]
    }
  ]

  def scenarios, do: @scenarios
end
```

- [ ] **Step 2: Implement `OrderFlow` context**

Create `lib/showcase/order_flow.ex`:

```elixir
defmodule Showcase.OrderFlow do
  @moduledoc """
  Public context for the OrderFlow demo.

  Used by LiveViews to enqueue work, list inbox messages, find orders.
  Used by tests to bulk-register mock Anthropic responses.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.{Order, SyntheticMessage}
  alias Showcase.OrderFlow.Worker
  alias Showcase.Repo

  @doc """
  Enqueue a random unprocessed synthetic message. Returns the job + message
  so the caller can subscribe to PubSub by message_id.
  """
  @spec enqueue_random() ::
          {:ok, Oban.Job.t(), SyntheticMessage.t()} | {:error, :no_messages}
  def enqueue_random do
    case unprocessed_messages() do
      [] -> {:error, :no_messages}
      msgs ->
        msg = Enum.random(msgs)
        {:ok, job} = Worker.new(%{message_id: msg.id}) |> Oban.insert()
        {:ok, job, msg}
    end
  end

  defp unprocessed_messages do
    subquery =
      from o in Order,
        where: not is_nil(o.synthetic_message_id),
        select: o.synthetic_message_id

    from(m in SyntheticMessage,
      where: m.id not in subquery(subquery)
    )
    |> Repo.all()
  end

  @doc "All seeded synthetic messages."
  def list_messages, do: Repo.all(from m in SyntheticMessage, order_by: [asc: m.id])

  @doc "All orders, most recent first."
  def list_orders do
    from(o in Order, order_by: [desc: o.inserted_at], preload: [:client, lines: :product])
    |> Repo.all()
  end

  @doc "Fetch an order with its lines + client."
  def find_order(id) do
    Repo.get(Order, id) |> Repo.preload([:client, lines: :product])
  end

  @doc """
  Register mock responses for every scenario in `MockPrompts.scenarios/0`.
  Call from test setup (only the Mock impl is active in test env).
  """
  def register_mock_responses do
    Enum.each(MockPrompts.scenarios(), fn s ->
      Mock.register("order_flow:extract:v1",
        scenario: s.name,
        text: s.extract_response
      )

      Enum.each(s.fallback_responses, fn fr ->
        Mock.register("order_flow:claude_fallback:v1",
          scenario: fr.scenario,
          text: fr.text
        )
      end)
    end)
  end
end
```

- [ ] **Step 3: Verify compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

- [ ] **Step 4: Verify tests unchanged**

```bash
mix test 2>&1 | tail -3
```

Should still show prior count (no tests added here).

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow.ex lib/showcase/order_flow/mock_prompts.ex
git commit -m "feat(order_flow): public context + MockPrompts bundle"
```

---

## Task 15: `OrderFlow.Seed` implementing DemoSeeder (TDD)

**Files:**
- Create: `lib/showcase/order_flow/seed.ex`
- Create: `test/showcase/order_flow/seed_test.exs`

**Contract:** Implements `Showcase.Common.DemoSeeder` callbacks: `name/0`, `tables/0`, `seed/0`, `oban_queue/0`. Idempotently seeds clients (Acme Inc, Beta Industries, Gamma Wholesale), products (a catalog of 8-12 SKUs), one client-scoped alias ("the 4mm gaskets we always order" → 4mm gasket, for Beta Industries), and all `MockPrompts.scenarios/0` as `SyntheticMessage` rows.

- [ ] **Step 1: Write failing tests**

Create `test/showcase/order_flow/seed_test.exs`:

```elixir
defmodule Showcase.OrderFlow.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Seed
  alias Showcase.OrderFlow.Schemas.{Client, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  test "name/0 returns 'OrderFlow'" do
    assert Seed.name() == "OrderFlow"
  end

  test "tables/0 returns of_* tables in child-before-parent order" do
    tables = Seed.tables()
    assert "of_order_lines" in tables
    assert "of_orders" in tables
    assert "of_product_aliases" in tables
    assert "of_synthetic_messages" in tables
    assert "of_products" in tables
    assert "of_clients" in tables
    # children before parents
    assert Enum.find_index(tables, &(&1 == "of_order_lines")) <
             Enum.find_index(tables, &(&1 == "of_orders"))
  end

  test "oban_queue/0 returns :order_flow" do
    assert Seed.oban_queue() == :order_flow
  end

  test "seed/0 populates clients, products, aliases, messages" do
    assert :ok = Seed.seed()

    assert Repo.aggregate(Client, :count) >= 3
    assert Repo.aggregate(Product, :count) >= 5
    assert Repo.aggregate(ProductAlias, :count) >= 1
    assert Repo.aggregate(SyntheticMessage, :count) >= 4
  end

  test "seed/0 is idempotent — running twice produces the same state" do
    assert :ok = Seed.seed()
    {clients_a, products_a, aliases_a, messages_a} = counts()

    assert :ok = Seed.seed()
    {clients_b, products_b, aliases_b, messages_b} = counts()

    assert clients_a == clients_b
    assert products_a == products_b
    assert aliases_a == aliases_b
    assert messages_a == messages_b
  end

  defp counts do
    {
      Repo.aggregate(Client, :count),
      Repo.aggregate(Product, :count),
      Repo.aggregate(ProductAlias, :count),
      Repo.aggregate(SyntheticMessage, :count)
    }
  end
end
```

- [ ] **Step 2: Run tests — confirm failures**

```bash
mix test test/showcase/order_flow/seed_test.exs
```

- [ ] **Step 3: Implement `Seed`**

Create `lib/showcase/order_flow/seed.ex`:

```elixir
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
    %{sku: "WGT-001", name: "Widget", normalized_name: "widget"},
    %{sku: "GDG-001", name: "Gadget", normalized_name: "gadget"},
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
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase/order_flow/seed_test.exs
```

Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/order_flow/seed.ex test/showcase/order_flow/seed_test.exs
git commit -m "feat(order_flow): Seed implementing DemoSeeder with idempotent inserts"
```

---

## Task 16: `InboxLive` — basic LiveView mount + render

**Files:**
- Create: `lib/showcase_web/live/order_flow/inbox_live.ex`
- Create: `test/showcase_web/live/order_flow/inbox_live_test.exs`

**Contract:** The OrderFlow demo LiveView. On mount: subscribes to a per-instance PubSub topic, calls `OrderFlow.register_mock_responses/0` once at startup (in non-prod envs), assigns the seeded inbox + current state. Renders inbox + pipeline pane + order list scaffold.

- [ ] **Step 1: Write a basic mount test**

Create `test/showcase_web/live/order_flow/inbox_live_test.exs`:

```elixir
defmodule ShowcaseWeb.OrderFlow.InboxLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Seed

  setup do
    Seed.seed()
    :ok
  end

  test "mounts and renders the inbox", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/order-flow")

    assert html =~ "OrderFlow"
    assert html =~ "Generate order"
  end

  test "shows seeded messages in the inbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    # at least one scenario name visible
    assert render(view) =~ "Acme Inc"
  end
end
```

- [ ] **Step 2: Add route**

Open `lib/showcase_web/router.ex`. In the public browser scope (where `get "/", PageController, :home` is), add:

```elixir
live "/order-flow", OrderFlow.InboxLive
```

- [ ] **Step 3: Implement `InboxLive` skeleton**

Create `lib/showcase_web/live/order_flow/inbox_live.ex`:

```elixir
defmodule ShowcaseWeb.OrderFlow.InboxLive do
  use ShowcaseWeb, :live_view

  alias Showcase.OrderFlow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Mock responses are registered once per LiveView mount in non-prod envs
      # (test env uses test setup; this is a safety net for dev demo).
      if Mix.env() != :prod do
        OrderFlow.register_mock_responses()
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "OrderFlow")
     |> assign(:messages, OrderFlow.list_messages())
     |> assign(:orders, OrderFlow.list_orders())
     |> assign(:active_message, nil)
     |> assign(:active_stages, initial_stages())
     |> assign(:active_lines, [])
     |> assign(:cascade_detail_open, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 p-6 min-h-screen">
      <section class="border rounded p-4">
        <header class="flex items-center justify-between mb-4">
          <h1 class="text-xl font-semibold">OrderFlow</h1>
          <button
            type="button"
            class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
            phx-click="generate_order"
          >
            Generate order
          </button>
        </header>

        <ol class="space-y-2">
          <li :for={msg <- @messages} class="text-sm border-l-2 border-zinc-200 pl-3">
            <p class="font-medium">{msg.client_hint || "(no client hint)"} · <span class="text-zinc-500">{msg.kind}</span></p>
            <p class="text-zinc-700 mt-1">{msg.body}</p>
          </li>
        </ol>
      </section>

      <section class="border rounded p-4">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Pipeline</h2>
        <%= if @active_message do %>
          <p class="text-sm text-zinc-700 mb-3">Processing: <span class="font-mono">{@active_message.scenario}</span></p>
        <% else %>
          <p class="text-sm text-zinc-500">Click "Generate order" to start.</p>
        <% end %>

        <%!-- stages and lines render in Task 17 --%>
      </section>
    </div>
    """
  end

  defp initial_stages do
    [
      %{label: "Extract", status: :pending},
      %{label: "Identify client", status: :pending},
      %{label: "Match lines", status: :pending},
      %{label: "Create order", status: :pending}
    ]
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase_web/live/order_flow/inbox_live_test.exs 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Verify the route works in dev**

```bash
PORT=4123 mix phx.server &
SERVER_PID=$!
sleep 3
echo "GET /order-flow → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4123/order-flow)"
kill $SERVER_PID 2>/dev/null
```

Expected: 200.

- [ ] **Step 6: Commit**

```bash
git add lib/showcase_web/live/order_flow/ lib/showcase_web/router.ex test/showcase_web/live/order_flow/
git commit -m "feat(web): OrderFlow.InboxLive skeleton with route + basic render"
```

---

## Task 17: Wire `Generate order` → enqueue worker → PubSub → live stage updates

**Files:**
- Modify: `lib/showcase_web/live/order_flow/inbox_live.ex`
- Modify: `test/showcase_web/live/order_flow/inbox_live_test.exs`

**Contract:** Clicking `Generate order` triggers `OrderFlow.enqueue_random/0`. The LiveView subscribes to the per-message PubSub topic. On each `:order_flow, <event>, payload` message, it updates `@active_stages` (which `PipelineStages` renders) and `@active_lines` (which `CascadeMatrix` renders).

- [ ] **Step 1: Add an event-flow test**

Append to `test/showcase_web/live/order_flow/inbox_live_test.exs`:

```elixir
  test "generate_order enqueues a worker and shows progress", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/order-flow")

    render_click(view, "generate_order", %{})

    # Pipeline runs asynchronously via Oban — for the test we have testing :manual,
    # so manually drain the queue.
    Oban.drain_queue(queue: :order_flow)

    # Render after drain — at minimum, an order count went up
    html = render(view)
    assert html =~ "Processing:"
  end
```

(This is intentionally a smoke check — the full PubSub round-trip is tricky in Oban :manual mode; we'll do a fuller LV interaction test in Task 22.)

- [ ] **Step 2: Update `InboxLive` with the event handlers**

Replace the placeholder section in `lib/showcase_web/live/order_flow/inbox_live.ex` to add event handlers + PubSub topic subscription. The full updated file:

```elixir
defmodule ShowcaseWeb.OrderFlow.InboxLive do
  use ShowcaseWeb, :live_view

  alias Showcase.OrderFlow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      if Mix.env() != :prod do
        OrderFlow.register_mock_responses()
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "OrderFlow")
     |> assign(:messages, OrderFlow.list_messages())
     |> assign(:orders, OrderFlow.list_orders())
     |> assign(:active_message, nil)
     |> assign(:active_stages, initial_stages())
     |> assign(:active_lines, [])
     |> assign(:cascade_detail_open, false)}
  end

  @impl true
  def handle_event("generate_order", _params, socket) do
    case OrderFlow.enqueue_random() do
      {:ok, _job, msg} ->
        topic = "order_flow:processing:#{msg.id}"
        Phoenix.PubSub.subscribe(Showcase.PubSub, topic)

        {:noreply,
         socket
         |> assign(:active_message, msg)
         |> assign(:active_stages, [
           %{label: "Extract", status: :running},
           %{label: "Identify client", status: :pending},
           %{label: "Match lines", status: :pending},
           %{label: "Create order", status: :pending}
         ])
         |> assign(:active_lines, [])}

      {:error, :no_messages} ->
        {:noreply, put_flash(socket, :info, "All messages processed — reset OrderFlow to start over.")}
    end
  end

  @impl true
  def handle_event("toggle_cascade_detail", _params, socket) do
    {:noreply, update(socket, :cascade_detail_open, &(!&1))}
  end

  @impl true
  def handle_info({:order_flow, :extracted, payload}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       List.update_at(stages, 0, &Map.put(&1, :status, :done))
       |> List.update_at(1, &Map.put(&1, :status, :running))
     end)
     |> put_flash(:info, "Extracted #{payload.line_count} line(s); hint: #{payload.client_hint}")}
  end

  def handle_info({:order_flow, :client_identified, _payload}, socket) do
    {:noreply,
     update(socket, :active_stages, fn stages ->
       List.update_at(stages, 1, &Map.put(&1, :status, :done))
       |> List.update_at(2, &Map.put(&1, :status, :running))
     end)}
  end

  def handle_info({:order_flow, :line_matched, payload}, socket) do
    {:noreply,
     update(socket, :active_lines, fn lines ->
       lines ++ [payload]
     end)}
  end

  def handle_info({:order_flow, :order_created, %{order_id: order_id}}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       Enum.map(stages, &Map.put(&1, :status, :done))
     end)
     |> assign(:orders, OrderFlow.list_orders())
     |> put_flash(:info, "Order ##{order_id} created.")}
  end

  def handle_info({:order_flow, :client_unresolved, %{reason: reason}}, socket) do
    {:noreply,
     socket
     |> update(:active_stages, fn stages ->
       List.update_at(stages, 1, &Map.put(&1, :status, :failed))
     end)
     |> put_flash(:error, "Client unresolved: #{reason}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 p-6 min-h-screen">
      <section class="border rounded p-4">
        <header class="flex items-center justify-between mb-4">
          <h1 class="text-xl font-semibold">OrderFlow</h1>
          <button
            type="button"
            class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
            phx-click="generate_order"
          >
            Generate order
          </button>
        </header>

        <ol class="space-y-2">
          <li :for={msg <- @messages} class={[
            "text-sm border-l-2 pl-3",
            @active_message && @active_message.id == msg.id && "border-emerald-400 bg-emerald-50",
            !(@active_message && @active_message.id == msg.id) && "border-zinc-200"
          ]}>
            <p class="font-medium">{msg.client_hint || "(no client hint)"} · <span class="text-zinc-500">{msg.kind}</span></p>
            <p class="text-zinc-700 mt-1">{msg.body}</p>
          </li>
        </ol>
      </section>

      <section class="border rounded p-4">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Pipeline</h2>
        <%= if @active_message do %>
          <p class="text-sm text-zinc-700 mb-3">Processing: <span class="font-mono">{@active_message.scenario}</span></p>
          <ShowcaseWeb.Components.PipelineStages.pipeline_stages stages={@active_stages} />

          <button
            type="button"
            class="mt-4 text-xs text-zinc-500 underline"
            phx-click="toggle_cascade_detail"
          >
            {if @cascade_detail_open, do: "Hide", else: "Show"} cascade detail
          </button>

          <%= if @cascade_detail_open and @active_lines != [] do %>
            <div class="mt-3 space-y-2">
              <div :for={line <- @active_lines} class="rounded border border-zinc-200 p-2 text-sm">
                <p class="font-mono">{line.description}</p>
                <p class="text-xs text-zinc-500 mt-1">
                  step: <span class="font-mono">{line.step}</span>
                  · conf: {if line.confidence, do: Float.round(line.confidence, 2), else: "—"}
                  · matched: {line.matched}
                </p>
              </div>
            </div>
          <% end %>
        <% else %>
          <p class="text-sm text-zinc-500">Click "Generate order" to start.</p>
        <% end %>

        <%= if @orders != [] do %>
          <div class="mt-6">
            <h3 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Recent orders</h3>
            <ol class="space-y-2">
              <li :for={order <- Enum.take(@orders, 5)} class="text-sm">
                <a class="underline" href={"/order-flow/orders/#{order.id}"}>
                  Order #{order.id} · {order.client && order.client.name} · {length(order.lines)} line(s)
                </a>
              </li>
            </ol>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp initial_stages do
    [
      %{label: "Extract", status: :pending},
      %{label: "Identify client", status: :pending},
      %{label: "Match lines", status: :pending},
      %{label: "Create order", status: :pending}
    ]
  end
end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/showcase_web/live/order_flow/inbox_live_test.exs 2>&1 | tail -5
```

Expected: 3 tests, 0 failures.

- [ ] **Step 4: Run full suite**

```bash
mix test 2>&1 | tail -3
```

Expected: all OrderFlow + prior Phase 0 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase_web/live/order_flow/inbox_live.ex test/showcase_web/live/order_flow/inbox_live_test.exs
git commit -m "feat(web): wire Generate order + PubSub stage updates in InboxLive"
```

---

## Task 18: Order detail LiveView with correction UI

**Files:**
- Create: `lib/showcase_web/live/order_flow/order_detail_live.ex`
- Create: `test/showcase_web/live/order_flow/order_detail_live_test.exs`

**Contract:** `GET /order-flow/orders/:id` shows the order's lines. Each line with `product_id` shows the matched product + cascade step + confidence. Each line with `product_id == nil` OR low confidence shows a "Correct" dropdown listing all products; selecting one updates the line AND writes a `ProductAlias` row (`source: "correction"`, `client_id: order.client_id`, `confidence: 0.9`, `last_used_at: now`).

- [ ] **Step 1: Write tests for the correction round-trip**

Create `test/showcase_web/live/order_flow/order_detail_live_test.exs`:

```elixir
defmodule ShowcaseWeb.OrderFlow.OrderDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Schemas.{Client, Order, OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  setup do
    {:ok, client} = Repo.insert(%Client{name: "Acme Inc"})

    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, order} =
      %Order{}
      |> Order.changeset(%{client_id: client.id, status: "pending_review"})
      |> Repo.insert()

    {:ok, line} =
      %OrderLine{}
      |> OrderLine.changeset(%{
        order_id: order.id,
        product_id: nil,
        raw_description: "mystery thing",
        quantity: 3,
        confidence: nil,
        match_step: nil
      })
      |> Repo.insert()

    {:ok, %{order: order, client: client, line: line, widget: widget}}
  end

  test "renders order with unmatched lines and a correction dropdown",
       %{conn: conn, order: order} do
    {:ok, _view, html} = live(conn, "/order-flow/orders/#{order.id}")

    assert html =~ "mystery thing"
    assert html =~ "Correct"
  end

  test "submitting a correction updates the line and writes a ProductAlias",
       %{conn: conn, order: order, client: client, line: line, widget: widget} do
    {:ok, view, _html} = live(conn, "/order-flow/orders/#{order.id}")

    render_change(view, "correct_line", %{
      "line_id" => line.id,
      "product_id" => widget.id
    })

    updated_line = Repo.get!(OrderLine, line.id)
    assert updated_line.product_id == widget.id

    alias_row =
      Repo.get_by!(ProductAlias,
        normalized_text: "mystery thing",
        client_id: client.id,
        product_id: widget.id
      )

    assert alias_row.source == "correction"
    assert alias_row.confidence >= 0.85
  end

  test "promotes to a global alias when ≥2 distinct clients have corrected the same mapping",
       %{conn: conn, order: order, client: client, line: line, widget: widget} do
    # Pre-seed: a correction from a different client already exists with high confidence.
    {:ok, other_client} = Repo.insert(%Client{name: "Other Co"})

    %ProductAlias{}
    |> ProductAlias.changeset(%{
      normalized_text: "mystery thing",
      product_id: widget.id,
      client_id: other_client.id,
      confidence: 0.9,
      last_used_at: DateTime.utc_now(),
      use_count: 1,
      source: "correction"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/order-flow/orders/#{order.id}")

    render_change(view, "correct_line", %{
      "line_id" => line.id,
      "product_id" => widget.id
    })

    # After the correction: 2 distinct clients now have the mapping with high confidence.
    # A global alias (client_id: nil) should have been created.
    global =
      Repo.get_by(ProductAlias,
        normalized_text: "mystery thing",
        product_id: widget.id,
        client_id: nil
      )

    assert global != nil
    assert global.source == "promotion"
    assert global.confidence >= 0.7
  end
end
```

- [ ] **Step 2: Add route**

In `lib/showcase_web/router.ex`, in the public scope, add:

```elixir
live "/order-flow/orders/:id", OrderFlow.OrderDetailLive
```

- [ ] **Step 3: Implement `OrderDetailLive`**

Create `lib/showcase_web/live/order_flow/order_detail_live.ex`:

```elixir
defmodule ShowcaseWeb.OrderFlow.OrderDetailLive do
  use ShowcaseWeb, :live_view

  import Ecto.Query

  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Impl.Normalize
  alias Showcase.OrderFlow.Schemas.{OrderLine, Product, ProductAlias}
  alias Showcase.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = OrderFlow.find_order(String.to_integer(id))

    {:ok,
     socket
     |> assign(:page_title, "Order ##{order.id}")
     |> assign(:order, order)
     |> assign(:products, Repo.all(from p in Product, order_by: p.name))}
  end

  @impl true
  def handle_event("correct_line", %{"line_id" => line_id, "product_id" => product_id}, socket) do
    line = Repo.get!(OrderLine, String.to_integer(line_id))
    product = Repo.get!(Product, String.to_integer(product_id))
    order = socket.assigns.order

    Repo.transaction(fn ->
      line
      |> OrderLine.changeset(%{product_id: product.id, match_step: "correction", confidence: 0.9})
      |> Repo.update!()

      now = DateTime.utc_now()
      normalized = Normalize.normalize_text(line.raw_description)

      case Repo.get_by(ProductAlias,
             normalized_text: normalized,
             client_id: order.client_id,
             product_id: product.id
           ) do
        nil ->
          %ProductAlias{}
          |> ProductAlias.changeset(%{
            normalized_text: normalized,
            product_id: product.id,
            client_id: order.client_id,
            confidence: 0.9,
            last_used_at: now,
            use_count: 1,
            source: "correction"
          })
          |> Repo.insert!()

        existing ->
          existing
          |> ProductAlias.changeset(%{
            confidence: min(existing.confidence + 0.05, 1.0),
            use_count: existing.use_count + 1,
            last_used_at: now
          })
          |> Repo.update!()
      end

      # After writing/updating the client-scoped alias, check if the
      # (normalized_text → product_id) mapping is now eligible for global
      # promotion (≥2 distinct clients with avg confidence ≥ 0.7).
      maybe_promote_to_global(normalized, product.id, now)
    end)

    {:noreply,
     socket
     |> assign(:order, OrderFlow.find_order(order.id))
     |> put_flash(:info, "Corrected. Future runs on this client will match without the LLM.")}
  end

  defp maybe_promote_to_global(normalized_text, product_id, now) do
    alias Showcase.OrderFlow.Impl.AliasPromotion

    # Look at all client-scoped aliases for this (normalized_text, product_id)
    entries =
      Repo.all(
        from a in ProductAlias,
          where:
            a.normalized_text == ^normalized_text and
              a.product_id == ^product_id and
              not is_nil(a.client_id),
          select: %{client_id: a.client_id, confidence: a.confidence}
      )

    if AliasPromotion.eligible_for_global?(entries) do
      # Insert a global alias if one doesn't already exist for this mapping
      existing_global =
        Repo.get_by(ProductAlias,
          normalized_text: normalized_text,
          product_id: product_id,
          client_id: nil
        )

      unless existing_global do
        avg_confidence =
          entries
          |> Enum.map(& &1.confidence)
          |> then(fn xs -> Enum.sum(xs) / length(xs) end)

        %ProductAlias{}
        |> ProductAlias.changeset(%{
          normalized_text: normalized_text,
          product_id: product_id,
          client_id: nil,
          confidence: avg_confidence,
          last_used_at: now,
          use_count: length(entries),
          source: "promotion"
        })
        |> Repo.insert!()
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <a href="/order-flow" class="text-sm text-zinc-500 underline">&larr; Inbox</a>
      <h1 class="text-2xl font-semibold mt-2">Order #{@order.id}</h1>
      <p class="text-sm text-zinc-700 mt-1">
        Client: <span class="font-medium">{@order.client && @order.client.name}</span>
        · Status: <span class="font-mono">{@order.status}</span>
        · {length(@order.lines)} line(s)
      </p>

      <table class="mt-6 w-full text-sm">
        <thead class="text-left text-zinc-500 uppercase tracking-wide text-xs">
          <tr>
            <th class="py-2">Raw description</th>
            <th class="py-2">Qty</th>
            <th class="py-2">Matched product</th>
            <th class="py-2">Step</th>
            <th class="py-2">Confidence</th>
            <th class="py-2">Correct</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @order.lines} class="border-t">
            <td class="py-3 font-mono">{line.raw_description}</td>
            <td class="py-3">{line.quantity}</td>
            <td class="py-3">{line.product && line.product.name || "—"}</td>
            <td class="py-3 font-mono">{line.match_step || "—"}</td>
            <td class="py-3">{if line.confidence, do: Float.round(line.confidence, 2), else: "—"}</td>
            <td class="py-3">
              <form phx-change="correct_line">
                <input type="hidden" name="line_id" value={line.id} />
                <select name="product_id" class="rounded border border-zinc-300 px-2 py-1 text-xs">
                  <option value="">Correct…</option>
                  <option :for={p <- @products} value={p.id} selected={line.product_id == p.id}>
                    {p.name} ({p.sku})
                  </option>
                </select>
              </form>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run tests until they pass**

```bash
mix test test/showcase_web/live/order_flow/order_detail_live_test.exs 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase_web/live/order_flow/order_detail_live.ex test/showcase_web/live/order_flow/order_detail_live_test.exs lib/showcase_web/router.ex
git commit -m "feat(web): OrderDetailLive with correction-writes-ProductAlias loop"
```

---

## Task 19: Self-improving loop integration test

**Files:**
- Create: `test/showcase/order_flow/self_improving_loop_test.exs`

**Contract:** End-to-end test demonstrating the key teaching point: run a message → see the LLM called → correct a mismatched line → re-run the same message → see the LLM NOT called (cascade matches via the freshly-written ProductAlias).

- [ ] **Step 1: Write the integration test**

Create `test/showcase/order_flow/self_improving_loop_test.exs`:

```elixir
defmodule Showcase.OrderFlow.SelfImprovingLoopTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow
  alias Showcase.OrderFlow.Pipeline
  alias Showcase.OrderFlow.Schemas.{Client, OrderLine, Product, ProductAlias, SyntheticMessage}
  alias Showcase.Repo

  setup do
    Mock.reset()
    OrderFlow.register_mock_responses()
    OrderFlow.Seed.seed()

    msg = Repo.get_by!(SyntheticMessage, scenario: "mixed_known_unknown")
    {:ok, %{message: msg}}
  end

  test "after a correction, re-running the same message uses the new alias instead of LLM fallback",
       %{message: msg} do
    # First run — "those gizmo things" gets matched via Claude fallback (per Mock registration).
    {:ok, order1} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    gizmo_line =
      Repo.preload(order1, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "gizmo"))

    assert gizmo_line.match_step == "claude_fallback"

    # Correct it: link to Gadget product manually, simulating the operator UI action.
    gadget = Repo.get_by!(Product, sku: "GDG-001")
    client = Repo.get_by!(Client, name: "Acme Inc")
    now = DateTime.utc_now()

    %ProductAlias{}
    |> ProductAlias.changeset(%{
      normalized_text: Showcase.OrderFlow.Impl.Normalize.normalize_text(gizmo_line.raw_description),
      product_id: gadget.id,
      client_id: client.id,
      confidence: 0.9,
      last_used_at: now,
      use_count: 1,
      source: "correction"
    })
    |> Repo.insert!()

    # Drop the order — pretend the operator ran the same message again.
    Repo.delete!(order1)

    # Re-run the same message — this time the client_alias step should hit, no LLM call.
    {:ok, order2} = Pipeline.process_message(msg, %{now: DateTime.utc_now()})

    gizmo_line2 =
      Repo.preload(order2, :lines).lines
      |> Enum.find(&(&1.raw_description =~ "gizmo"))

    assert gizmo_line2.match_step == "client_alias"
    assert gizmo_line2.product_id == gadget.id
  end
end
```

- [ ] **Step 2: Run the integration test**

```bash
mix test test/showcase/order_flow/self_improving_loop_test.exs 2>&1 | tail -10
```

Expected: 1 test, 0 failures.

- [ ] **Step 3: Run full suite**

```bash
mix test 2>&1 | tail -3
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add test/showcase/order_flow/self_improving_loop_test.exs
git commit -m "test(order_flow): self-improving loop end-to-end integration"
```

---

## Task 20: Reset integration + dashboard tile + smoke test

**Files:**
- Modify: `lib/showcase_web/live/admin/reset_live.ex` (wire to call `Reset.run([OrderFlow.Seed])`)
- Modify: `lib/showcase_web/components/...` (if dashboard tile needs an OrderFlow card — but Phase 0 didn't ship the dashboard surface; defer that to Phase 2)
- Modify: `lib/showcase_web/router.ex` (verify routes)
- Modify: `test/showcase/common/reset_test.exs` (add integration test using `OrderFlow.Seed` as a real seeder)

- [ ] **Step 1: Add Reset integration test**

Append to `test/showcase/common/reset_test.exs`:

```elixir
  describe "with OrderFlow.Seed" do
    alias Showcase.OrderFlow.Schemas.{Client, Product, SyntheticMessage}
    alias Showcase.OrderFlow.Seed

    setup do
      Seed.seed()
      :ok
    end

    test "reset re-seeds OrderFlow from scratch" do
      Repo.delete_all(SyntheticMessage)
      assert Repo.aggregate(SyntheticMessage, :count) == 0

      assert :ok = Reset.run([Seed])

      assert Repo.aggregate(Client, :count) >= 3
      assert Repo.aggregate(Product, :count) >= 5
      assert Repo.aggregate(SyntheticMessage, :count) >= 4
    end
  end
```

- [ ] **Step 2: Replace `ResetLive` stub with a button that resets OrderFlow**

Replace `lib/showcase_web/live/admin/reset_live.ex` contents with:

```elixir
defmodule ShowcaseWeb.Admin.ResetLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.Reset

  @seeders [Showcase.OrderFlow.Seed]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset (admin)")
     |> assign(:last_reset_at, nil)}
  end

  @impl true
  def handle_event("reset_all", _params, socket) do
    case Reset.run(@seeders) do
      :ok ->
        {:noreply,
         socket
         |> assign(:last_reset_at, DateTime.utc_now())
         |> put_flash(:info, "Demos reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-2xl">
      <h1 class="text-xl font-semibold">Reset demo data</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Click to TRUNCATE per-demo tables + re-seed. Resets in-flight Oban jobs first.
      </p>

      <button
        type="button"
        class="mt-4 rounded bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700"
        phx-click="reset_all"
        data-confirm="Reset all demos? This wipes demo data."
      >
        Reset OrderFlow
      </button>

      <%= if @last_reset_at do %>
        <p class="text-xs text-zinc-500 mt-3">Last reset: <span class="font-mono">{@last_reset_at}</span></p>
      <% end %>
    </div>
    """
  end
end
```

- [ ] **Step 3: Verify the reset works end-to-end via the admin route**

```bash
mix test 2>&1 | tail -3
PORT=4123 mix phx.server &
SERVER_PID=$!
sleep 3
echo "GET /order-flow → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4123/order-flow)"
echo "GET /admin/reset auth → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4123/admin/reset)"
kill $SERVER_PID 2>/dev/null
```

Expected: 200 on both.

- [ ] **Step 4: Commit**

```bash
git add lib/showcase_web/live/admin/reset_live.ex test/showcase/common/reset_test.exs
git commit -m "feat(web): wire ResetLive to OrderFlow.Seed; add Reset integration test"
```

---

## Task 21: Final smoke test + phase-1 tag

**Files:** none modified — verification only.

- [ ] **Step 1: Full test suite**

```bash
mix test 2>&1 | tail -5
```

Expected: tests significantly higher than 40 (≈ 65-75 including all OrderFlow tests + Phase 0 tests).

- [ ] **Step 2: Boot the server**

```bash
PORT=4123 mix phx.server &
SERVER_PID=$!
sleep 3
```

- [ ] **Step 3: Verify routes**

```bash
echo "GET /                          → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4123/)"
echo "GET /order-flow                → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4123/order-flow)"
echo "GET /admin/reset auth          → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4123/admin/reset)"
echo "GET /admin/dashboard auth      → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4123/admin/dashboard)"

kill $SERVER_PID 2>/dev/null
```

Expected: all 200 (admin/dashboard may 302 to its default subpage).

- [ ] **Step 4: Compile clean**

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

Expected: clean.

- [ ] **Step 5: Tag**

```bash
git tag -a phase-1 -m "Phase 1 OrderFlow complete: demo end-to-end, cascade matching, self-improving aliases, correction loop"
git tag -l 'phase-*'
```

Expected: `phase-0` and `phase-1` both listed.

---

## Phase 1 acceptance criteria

When all tasks above are complete and committed:

- [ ] `mix test` green; new OrderFlow tests added (~25-30 tests)
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `GET /order-flow` renders the inbox + pipeline pane (200)
- [ ] `GET /order-flow/orders/<id>` renders the order detail + correction UI (200)
- [ ] `GET /admin/reset` wired to TRUNCATE + re-seed via `OrderFlow.Seed` (200, gated by basic auth)
- [ ] `Showcase.OrderFlow.Pipeline.process_message/2` runs the full 5-step cascade, broadcasts PubSub events, creates `Order` + `OrderLine` rows
- [ ] Self-improving loop test passes: corrected alias is used on subsequent runs, skipping the LLM
- [ ] `phase-1` tag in git history

The next plan (Phase 2: Dashboard shell) builds the value-framed tile launcher around OrderFlow as the first attached demo.
