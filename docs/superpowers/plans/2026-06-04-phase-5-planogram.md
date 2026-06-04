# Phase 5 — Planogram Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Planogram Manager demo — retail shelf compliance via a single Claude vision call, returning a rich JSON result (score, per-row breakdown, issues, suggestions, extracted products) that LiveView renders with a compliance gauge, JSON inspector, and cost badge. Role switcher in the chrome (Admin / Manager / Merchandiser). Mobile QR handoff lets the AE photograph a shelf with their phone and have the result stream back to the desktop view.

**Architecture:**
- One Phoenix LiveView at `/planogram`, role-switched via session (not separate URLs). One handoff LiveView at `/planogram/mobile/:token`.
- 2 tables under the `pg_` prefix: `pg_planograms` (reference shelf layouts) + `pg_verification_tasks` (the audit rows).
- `VerificationTask` carries 4 statuses: `pending` / `analyzing` / `complete` / `failed` (Oban worker drives transitions). Overdue is computed at query time from `due_date`, never written.
- A single rich-JSON Claude vision call routed via `AnthropicClient` (Live for real, Mock keyed by scenario in tests). Result salvaged with `ResilientJSONParser`, persisted as JSONB.
- Photos live on the filesystem under `priv/static/uploads/planogram/` (cleaned on reset). Bundled reference images live under `priv/static/images/planogram/`.
- Mobile handoff: each pending task carries a random `mobile_token`. The Merchandiser view renders `eqrcode` SVG of `/planogram/mobile/:token`. The phone uploads via Phoenix LiveUpload; the desktop receives the result via PubSub.
- Force-truncation hidden toggle on the Merchandiser view caps `max_tokens: 200` so AEs can demo `ResilientJSONParser`'s `:partial` salvage path live.
- 3 bundled scenarios in the seed: `compliant` / `minor_issues` / `major_issues`. Each ships a reference image + a synthetic captured photo + a canned mock JSON response.

**Tech Stack:**
- Phoenix 1.8.7 LiveView 1.1 + Ecto 3.13 + AshPostgres 2.x (we use plain Ecto for `pg_*` tables — Ash earns its keep on `SystemPrompt`/`AuditLog` only)
- Oban 2.x free, queue `:planogram` (already configured in `config/config.exs:76`)
- `eqrcode 0.2` for QR SVG generation (already pinned in `mix.exs:55`)
- `Showcase.Common.AnthropicClient` — vision messages use the standard Claude content-block format (`%{type: "image", source: %{...}}`)
- `Showcase.Common.ResilientJSONParser` for `:partial` salvage
- `Phoenix.LiveView.Upload` for the mobile photo capture
- `Phoenix.PubSub` topic `"planogram:task:<id>"` for cross-device progress propagation

---

## File Structure

**New schemas (Ecto):**
- `lib/showcase/planogram/planogram.ex` — `pg_planograms` schema
- `lib/showcase/planogram/verification_task.ex` — `pg_verification_tasks` schema

**Pure modules (no DB / no clock / no HTTP):**
- `lib/showcase/planogram/impl/overdue.ex` — computed `overdue?/2`
- `lib/showcase/planogram/impl/vision_request.ex` — builds the Claude content blocks (text + base64 image) and system prompt
- `lib/showcase/planogram/impl/result_renderer.ex` — view-model: takes raw JSON, returns `%{gauge_pct, per_row, issues, suggestions, products, photo_quality}` with sensible defaults for missing fields (so `:partial` results still render)

**Boundary modules:**
- `lib/showcase/planogram/vision_pipeline.ex` — orchestration: read file → build request → call Anthropic → parse → persist → broadcast
- `lib/showcase/planogram/worker.ex` — Oban worker
- `lib/showcase/planogram/mobile_handoff.ex` — token generation + path resolution + upload finalization
- `lib/showcase/planogram/mock_prompts.ex` — registers 3 scenarios on the Mock
- `lib/showcase/planogram/seed.ex` — implements `DemoSeeder`
- `lib/showcase/planogram.ex` — public context module (CRUD + enqueue + role-switching helpers)

**Web:**
- `lib/showcase_web/live/planogram/planogram_live.ex` — single LiveView, role-switched render at `/planogram`
- `lib/showcase_web/live/planogram/mobile_capture_live.ex` — `/planogram/mobile/:token`
- `lib/showcase_web/live/planogram/components/compliance_gauge.ex` — circular gauge function component
- `lib/showcase_web/live/planogram/components/per_row_table.ex` — per-row breakdown table
- `lib/showcase_web/live/planogram/components/qr_handoff.ex` — QR code SVG component
- `lib/showcase_web/router.ex` — add `/planogram` + `/planogram/mobile/:token` routes

**Assets:**
- `priv/static/images/planogram/reference_3-shelf-snacks.png` (bundled reference, base64 stub in seed for tests)
- `priv/static/images/planogram/captured_compliant.png`
- `priv/static/images/planogram/captured_minor_issues.png`
- `priv/static/images/planogram/captured_major_issues.png`

(Images: the seed ships **tiny PNG placeholders** committed to the repo so dev/CI has stable bytes. Real Anthropic vision testing happens manually via `ANTHROPIC_API_KEY` against the dev server.)

**Tests:**
- `test/showcase/planogram/impl/overdue_test.exs`
- `test/showcase/planogram/impl/vision_request_test.exs`
- `test/showcase/planogram/impl/result_renderer_test.exs`
- `test/showcase/planogram/mock_prompts_test.exs`
- `test/showcase/planogram/vision_pipeline_test.exs`
- `test/showcase/planogram/worker_test.exs`
- `test/showcase/planogram/mobile_handoff_test.exs`
- `test/showcase/planogram/seed_test.exs`
- `test/showcase_web/live/planogram/planogram_live_test.exs`
- `test/showcase_web/live/planogram/mobile_capture_live_test.exs`

---

## Tasks

### Task 1: Planogram schemas + migration

**Files:**
- Create: `lib/showcase/planogram/planogram.ex`
- Create: `lib/showcase/planogram/verification_task.ex`
- Create: `priv/repo/migrations/<timestamp>_create_planogram_schemas.exs`

- [ ] **Step 1: Generate migration timestamp**

Run: `date -u +"%Y%m%d%H%M%S"` to get a timestamp like `20260605091500`. Use it as the migration filename prefix.

- [ ] **Step 2: Write the migration**

File: `priv/repo/migrations/<timestamp>_create_planogram_schemas.exs`

```elixir
defmodule Showcase.Repo.Migrations.CreatePlanogramSchemas do
  use Ecto.Migration

  def change do
    create table(:pg_planograms) do
      add :name, :string, null: false
      add :description, :text
      add :reference_image_path, :string, null: false
      # JSONB of expected rows: [%{name, position, products: [%{sku, name, qty}]}, ...]
      add :expected_rows, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pg_planograms, [:name])

    create table(:pg_verification_tasks) do
      add :planogram_id, references(:pg_planograms, on_delete: :delete_all), null: false
      add :store_name, :string, null: false
      add :due_date, :date, null: false
      add :status, :string, null: false, default: "pending"
      # filesystem path under priv/static/ (nil until photo captured)
      add :photo_path, :string
      # single-use mobile-handoff token, unique
      add :mobile_token, :string, null: false
      # canned scenario tag used by Mock + bundled seed photos
      add :scenario, :string, null: false, default: "compliant"
      # vision call result (rich JSON from Claude), nil until complete
      add :result, :map
      # %{input_tokens, output_tokens, cost_estimate_cents}, nil until complete
      add :usage, :map
      add :error_reason, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pg_verification_tasks, [:mobile_token])
    create index(:pg_verification_tasks, [:planogram_id])
    create index(:pg_verification_tasks, [:status])
    create index(:pg_verification_tasks, [:due_date])
  end
end
```

- [ ] **Step 3: Write the Planogram schema**

File: `lib/showcase/planogram/planogram.ex`

```elixir
defmodule Showcase.Planogram.Planogram do
  @moduledoc """
  Reference shelf layout. One row per planogram a Manager has authored.

  `expected_rows` is a JSONB document of shape:

      %{
        "rows" => [
          %{
            "name" => "Top shelf",
            "position" => 1,
            "products" => [
              %{"sku" => "SKU-001", "name" => "Coca-Cola 500ml", "qty" => 6}
            ]
          }
        ]
      }
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "pg_planograms" do
    field :name, :string
    field :description, :string
    field :reference_image_path, :string
    field :expected_rows, :map, default: %{"rows" => []}

    has_many :verification_tasks, Showcase.Planogram.VerificationTask, foreign_key: :planogram_id

    timestamps(type: :utc_datetime)
  end

  def changeset(planogram, attrs) do
    planogram
    |> cast(attrs, [:name, :description, :reference_image_path, :expected_rows])
    |> validate_required([:name, :reference_image_path])
    |> unique_constraint(:name)
  end
end
```

- [ ] **Step 4: Write the VerificationTask schema**

File: `lib/showcase/planogram/verification_task.ex`

```elixir
defmodule Showcase.Planogram.VerificationTask do
  @moduledoc """
  An audit row: planogram + store + due date + (eventually) captured photo + result.

  Status values:
    * `"pending"`   — created, no photo captured yet, OR photo captured but analysis not started
    * `"analyzing"` — Oban worker running the vision call
    * `"complete"`  — vision call succeeded (possibly with :partial JSON salvage)
    * `"failed"`    — vision call failed after retries (Anthropic 5xx, etc.)

  Overdue is NOT a status — it's a computed field via `Showcase.Planogram.Impl.Overdue.overdue?/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending analyzing complete failed)

  schema "pg_verification_tasks" do
    field :store_name, :string
    field :due_date, :date
    field :status, :string, default: "pending"
    field :photo_path, :string
    field :mobile_token, :string
    field :scenario, :string, default: "compliant"
    field :result, :map
    field :usage, :map
    field :error_reason, :string

    belongs_to :planogram, Showcase.Planogram.Planogram

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :planogram_id,
      :store_name,
      :due_date,
      :status,
      :photo_path,
      :mobile_token,
      :scenario,
      :result,
      :usage,
      :error_reason
    ])
    |> validate_required([:planogram_id, :store_name, :due_date, :mobile_token, :scenario])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:mobile_token)
    |> assoc_constraint(:planogram)
  end

  def valid_statuses, do: @valid_statuses
end
```

- [ ] **Step 5: Run the migration**

Run: `mix ecto.migrate`
Expected: both tables created with indexes, no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/showcase/planogram/ priv/repo/migrations/
git commit -m "feat(planogram): schemas + migration (pg_planograms + pg_verification_tasks)"
```

---

### Task 2: Overdue pure module (TDD)

**Files:**
- Create: `lib/showcase/planogram/impl/overdue.ex`
- Test: `test/showcase/planogram/impl/overdue_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/impl/overdue_test.exs`

```elixir
defmodule Showcase.Planogram.Impl.OverdueTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.Overdue
  alias Showcase.Planogram.VerificationTask

  describe "overdue?/2" do
    test "false when due_date is today" do
      task = %VerificationTask{due_date: ~D[2026-06-04], status: "pending"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when due_date is tomorrow" do
      task = %VerificationTask{due_date: ~D[2026-06-05], status: "pending"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "true when due_date is yesterday and status is pending" do
      task = %VerificationTask{due_date: ~D[2026-06-03], status: "pending"}
      assert Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "true when due_date is in the past and status is analyzing" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "analyzing"}
      assert Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when status is complete regardless of due_date" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "complete"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when status is failed regardless of due_date" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "failed"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end
  end

  describe "bucket/2" do
    test "groups by today / tomorrow / overdue / later" do
      tasks = [
        %VerificationTask{id: 1, due_date: ~D[2026-06-04], status: "pending"},
        %VerificationTask{id: 2, due_date: ~D[2026-06-05], status: "pending"},
        %VerificationTask{id: 3, due_date: ~D[2026-06-03], status: "pending"},
        %VerificationTask{id: 4, due_date: ~D[2026-06-10], status: "pending"},
        %VerificationTask{id: 5, due_date: ~D[2026-06-01], status: "complete"}
      ]

      buckets = Overdue.bucket(tasks, ~D[2026-06-04])
      assert Enum.map(buckets.overdue, & &1.id) == [3]
      assert Enum.map(buckets.today, & &1.id) == [1]
      assert Enum.map(buckets.tomorrow, & &1.id) == [2]
      assert Enum.map(buckets.later, & &1.id) == [4]
      assert Enum.map(buckets.done, & &1.id) == [5]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/impl/overdue_test.exs`
Expected: FAIL with "module Showcase.Planogram.Impl.Overdue is not loaded".

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/impl/overdue.ex`

```elixir
defmodule Showcase.Planogram.Impl.Overdue do
  @moduledoc """
  Pure functions for the date-driven overdue logic.

  Overdue is a query-time computed property — no cron mutates a status to
  "overdue". This module takes a task + a clock (passed as `Date`) and
  returns a boolean / bucket. Boundary code supplies the date so tests can
  pin the clock.
  """

  alias Showcase.Planogram.VerificationTask

  @spec overdue?(VerificationTask.t(), Date.t()) :: boolean()
  def overdue?(%VerificationTask{status: status}, _today)
      when status in ["complete", "failed"],
      do: false

  def overdue?(%VerificationTask{due_date: due_date}, today) do
    Date.compare(due_date, today) == :lt
  end

  @doc """
  Partition a list of tasks into display buckets given today's date.

  Returns a map with keys `:overdue`, `:today`, `:tomorrow`, `:later`, `:done`.
  """
  @spec bucket(list(VerificationTask.t()), Date.t()) :: %{
          overdue: list(VerificationTask.t()),
          today: list(VerificationTask.t()),
          tomorrow: list(VerificationTask.t()),
          later: list(VerificationTask.t()),
          done: list(VerificationTask.t())
        }
  def bucket(tasks, today) do
    Enum.reduce(tasks, %{overdue: [], today: [], tomorrow: [], later: [], done: []}, fn task,
                                                                                        acc ->
      key = bucket_key(task, today)
      Map.update!(acc, key, &[task | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp bucket_key(%VerificationTask{status: s}, _today) when s in ["complete", "failed"], do: :done

  defp bucket_key(%VerificationTask{due_date: due_date}, today) do
    case Date.compare(due_date, today) do
      :lt ->
        :overdue

      :eq ->
        :today

      :gt ->
        if Date.diff(due_date, today) == 1, do: :tomorrow, else: :later
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/impl/overdue_test.exs`
Expected: PASS — all 8 assertions green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/impl/overdue.ex test/showcase/planogram/impl/overdue_test.exs
git commit -m "feat(planogram): Impl.Overdue pure module (query-time overdue computation)"
```

---

### Task 3: VisionRequest pure module (TDD)

**Files:**
- Create: `lib/showcase/planogram/impl/vision_request.ex`
- Test: `test/showcase/planogram/impl/vision_request_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/impl/vision_request_test.exs`

```elixir
defmodule Showcase.Planogram.Impl.VisionRequestTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.VisionRequest
  alias Showcase.Common.AnthropicClient.Types.Request

  describe "build/3" do
    test "produces a Request with system prompt, vision content blocks, and metadata" do
      planogram = %{
        name: "3-shelf snacks",
        expected_rows: %{
          "rows" => [
            %{"name" => "Top", "position" => 1, "products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]}
          ]
        }
      }

      photo_bytes = <<137, 80, 78, 71>>  # PNG magic
      scenario = "compliant"

      request = VisionRequest.build(planogram, photo_bytes, scenario: scenario)

      assert %Request{} = request
      assert request.system =~ "retail merchandising auditor"
      assert request.system =~ "JSON"
      assert request.metadata == %{fingerprint: "planogram_vision_v1", scenario: "compliant"}
      assert request.max_tokens == 4096

      # First content block is the image
      [%{"role" => "user", "content" => [image, text]}] = request.messages
      assert image["type"] == "image"
      assert image["source"]["type"] == "base64"
      assert image["source"]["media_type"] == "image/png"
      assert image["source"]["data"] == Base.encode64(photo_bytes)

      assert text["type"] == "text"
      assert text["text"] =~ "3-shelf snacks"
      assert text["text"] =~ "Top"
      assert text["text"] =~ "Coke"
    end

    test "honors :max_tokens override for the force-truncation demo" do
      planogram = %{name: "x", expected_rows: %{"rows" => []}}
      request = VisionRequest.build(planogram, <<>>, scenario: "compliant", max_tokens: 200)
      assert request.max_tokens == 200
    end

    test "infers image media type from photo_path when bytes start with PNG magic" do
      assert VisionRequest.media_type(<<137, 80, 78, 71, 0>>) == "image/png"
    end

    test "infers image media type as jpeg by default" do
      assert VisionRequest.media_type(<<0xFF, 0xD8, 0xFF, 0xE0>>) == "image/jpeg"
      assert VisionRequest.media_type(<<0, 0, 0>>) == "image/jpeg"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/impl/vision_request_test.exs`
Expected: FAIL (module not loaded).

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/impl/vision_request.ex`

```elixir
defmodule Showcase.Planogram.Impl.VisionRequest do
  @moduledoc """
  Pure builder for the planogram vision `AnthropicClient.Request`.

  Takes a planogram (with expected_rows) + photo bytes + opts, returns a
  Request with the vision content blocks, system prompt, and metadata
  keyed by `{fingerprint, scenario}` for Mock matching.

  Does NOT read the filesystem — boundary code reads the photo and passes
  bytes in.
  """

  alias Showcase.Common.AnthropicClient.Types.Request

  @fingerprint "planogram_vision_v1"

  @system_prompt """
  You are a retail merchandising auditor. Given a reference planogram
  (expected rows + products) and a photo of an actual shelf, return a
  STRICT JSON object with the following shape:

  {
    "compliance_score": <0-100 integer>,
    "executive_summary": "<one-paragraph readable summary>",
    "rows": [
      {
        "name": "<row name>",
        "position": <int>,
        "status": "compliant" | "partial" | "non_compliant",
        "found_products": [{"sku": "<sku>", "name": "<name>", "qty": <int>}],
        "issues": ["<short issue strings>"]
      }
    ],
    "issues": [
      {
        "type": "missing_product" | "wrong_position" | "wrong_qty" | "unauthorized_item" | "photo_quality",
        "severity": "low" | "medium" | "high",
        "description": "<text>",
        "business_impact": "<text>"
      }
    ],
    "unauthorized_items": [{"name": "<name>", "row": <int>}],
    "suggestions": ["<actionable suggestion>"],
    "photo_quality": {"score": <0-100>, "notes": "<text>"},
    "extracted_products": [{"sku": "<sku>", "name": "<name>", "qty": <int>}]
  }

  Output ONLY the JSON. No prose. No code fences.
  """

  @spec build(map(), binary(), keyword()) :: Request.t()
  def build(planogram, photo_bytes, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, "compliant")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    %Request{
      model: "claude-sonnet-4-5",
      system: @system_prompt,
      max_tokens: max_tokens,
      messages: [
        %{
          "role" => "user",
          "content" => [
            %{
              "type" => "image",
              "source" => %{
                "type" => "base64",
                "media_type" => media_type(photo_bytes),
                "data" => Base.encode64(photo_bytes)
              }
            },
            %{
              "type" => "text",
              "text" => user_text(planogram)
            }
          ]
        }
      ],
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }
  end

  @spec media_type(binary()) :: String.t()
  def media_type(<<137, 80, 78, 71, _::binary>>), do: "image/png"
  def media_type(_), do: "image/jpeg"

  @doc false
  def fingerprint, do: @fingerprint

  defp user_text(%{name: name, expected_rows: rows}) do
    """
    Reference planogram: "#{name}"

    Expected rows:
    #{Jason.encode!(rows, pretty: true)}

    The image attached above is a photo of the actual shelf. Audit
    compliance and return the JSON shape described in the system prompt.
    """
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/impl/vision_request_test.exs`
Expected: PASS — 4 assertions green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/impl/vision_request.ex test/showcase/planogram/impl/vision_request_test.exs
git commit -m "feat(planogram): Impl.VisionRequest pure builder for Claude vision call"
```

---

### Task 4: ResultRenderer pure module (TDD)

**Files:**
- Create: `lib/showcase/planogram/impl/result_renderer.ex`
- Test: `test/showcase/planogram/impl/result_renderer_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/impl/result_renderer_test.exs`

```elixir
defmodule Showcase.Planogram.Impl.ResultRendererTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.ResultRenderer

  describe "render/1" do
    test "maps a full result to view-model" do
      raw = %{
        "compliance_score" => 87,
        "executive_summary" => "Shelf is mostly in order.",
        "rows" => [
          %{"name" => "Top", "position" => 1, "status" => "compliant",
            "found_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}],
            "issues" => []}
        ],
        "issues" => [
          %{"type" => "missing_product", "severity" => "medium",
            "description" => "Sprite missing", "business_impact" => "Lost sales"}
        ],
        "unauthorized_items" => [],
        "suggestions" => ["Restock Sprite"],
        "photo_quality" => %{"score" => 95, "notes" => "Clear photo"},
        "extracted_products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]
      }

      vm = ResultRenderer.render(raw)
      assert vm.gauge_pct == 87
      assert vm.executive_summary == "Shelf is mostly in order."
      assert length(vm.rows) == 1
      assert hd(vm.rows).name == "Top"
      assert hd(vm.rows).status_color == "emerald"
      assert length(vm.issues) == 1
      assert hd(vm.issues).severity_color == "amber"
      assert vm.suggestions == ["Restock Sprite"]
      assert vm.photo_quality.score == 95
      refute vm.partial?
    end

    test "fills sensible defaults when fields are missing (:partial salvage)" do
      raw = %{"compliance_score" => 50, "rows" => []}
      vm = ResultRenderer.render(raw)

      assert vm.gauge_pct == 50
      assert vm.executive_summary == "(no summary returned)"
      assert vm.rows == []
      assert vm.issues == []
      assert vm.suggestions == []
      assert vm.photo_quality == %{score: nil, notes: nil}
      assert vm.extracted_products == []
      assert vm.partial?
    end

    test "color codes row status" do
      assert ResultRenderer.row_status_color("compliant") == "emerald"
      assert ResultRenderer.row_status_color("partial") == "amber"
      assert ResultRenderer.row_status_color("non_compliant") == "rose"
      assert ResultRenderer.row_status_color("anything-else") == "zinc"
    end

    test "color codes issue severity" do
      assert ResultRenderer.severity_color("low") == "zinc"
      assert ResultRenderer.severity_color("medium") == "amber"
      assert ResultRenderer.severity_color("high") == "rose"
      assert ResultRenderer.severity_color(nil) == "zinc"
    end

    test "clamps gauge to 0-100 range" do
      assert ResultRenderer.render(%{"compliance_score" => 120}).gauge_pct == 100
      assert ResultRenderer.render(%{"compliance_score" => -5}).gauge_pct == 0
      assert ResultRenderer.render(%{"compliance_score" => "bad"}).gauge_pct == 0
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/impl/result_renderer_test.exs`
Expected: FAIL (module not loaded).

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/impl/result_renderer.ex`

```elixir
defmodule Showcase.Planogram.Impl.ResultRenderer do
  @moduledoc """
  Pure mapper from raw vision JSON to view-model.

  Tolerates missing fields gracefully — `ResilientJSONParser` may return
  `:partial` results with arbitrary key drops. Every field has a default
  so the LiveView template never crashes on `nil`.

  Sets `:partial?` to true when key required fields are absent, so the UI
  can show a "response was malformed, here's what we recovered" banner.
  """

  @required ~w(executive_summary rows issues photo_quality)

  @spec render(map() | nil) :: map()
  def render(nil), do: render(%{})

  def render(raw) when is_map(raw) do
    %{
      gauge_pct: clamp_gauge(raw["compliance_score"]),
      executive_summary: raw["executive_summary"] || "(no summary returned)",
      rows: Enum.map(raw["rows"] || [], &render_row/1),
      issues: Enum.map(raw["issues"] || [], &render_issue/1),
      unauthorized_items: raw["unauthorized_items"] || [],
      suggestions: raw["suggestions"] || [],
      photo_quality: render_photo_quality(raw["photo_quality"]),
      extracted_products: raw["extracted_products"] || [],
      partial?: partial?(raw)
    }
  end

  defp clamp_gauge(n) when is_integer(n), do: max(0, min(100, n))
  defp clamp_gauge(n) when is_float(n), do: clamp_gauge(round(n))
  defp clamp_gauge(_), do: 0

  defp render_row(row) do
    %{
      name: row["name"] || "(unnamed row)",
      position: row["position"],
      status: row["status"] || "unknown",
      status_color: row_status_color(row["status"]),
      found_products: row["found_products"] || [],
      issues: row["issues"] || []
    }
  end

  defp render_issue(issue) do
    %{
      type: issue["type"] || "unknown",
      severity: issue["severity"] || "low",
      severity_color: severity_color(issue["severity"]),
      description: issue["description"] || "",
      business_impact: issue["business_impact"] || ""
    }
  end

  defp render_photo_quality(nil), do: %{score: nil, notes: nil}

  defp render_photo_quality(pq) when is_map(pq),
    do: %{score: pq["score"], notes: pq["notes"]}

  defp partial?(raw) do
    Enum.any?(@required, &(not Map.has_key?(raw, &1)))
  end

  @spec row_status_color(String.t() | nil) :: String.t()
  def row_status_color("compliant"), do: "emerald"
  def row_status_color("partial"), do: "amber"
  def row_status_color("non_compliant"), do: "rose"
  def row_status_color(_), do: "zinc"

  @spec severity_color(String.t() | nil) :: String.t()
  def severity_color("high"), do: "rose"
  def severity_color("medium"), do: "amber"
  def severity_color("low"), do: "zinc"
  def severity_color(_), do: "zinc"
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/impl/result_renderer_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/impl/result_renderer.ex test/showcase/planogram/impl/result_renderer_test.exs
git commit -m "feat(planogram): Impl.ResultRenderer view-model with :partial-tolerant defaults"
```

---

### Task 5: MockPrompts with 3 scenarios (TDD)

**Files:**
- Create: `lib/showcase/planogram/mock_prompts.ex`
- Test: `test/showcase/planogram/mock_prompts_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/mock_prompts_test.exs`

```elixir
defmodule Showcase.Planogram.MockPromptsTest do
  use ExUnit.Case, async: false

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Planogram.MockPrompts

  setup do
    Showcase.Common.AnthropicClient.Mock.reset()
    MockPrompts.register_all()
    :ok
  end

  describe "register_all/0" do
    test "registers compliant, minor_issues, major_issues scenarios" do
      for scenario <- ["compliant", "minor_issues", "major_issues"] do
        req = %Request{
          model: "claude-sonnet-4-5",
          messages: [%{"role" => "user", "content" => []}],
          metadata: %{fingerprint: "planogram_vision_v1", scenario: scenario}
        }

        assert {:ok, resp} = AnthropicClient.call(req)
        assert is_binary(resp.text)
        parsed = Jason.decode!(resp.text)
        assert is_integer(parsed["compliance_score"])
      end
    end

    test "compliant scenario returns score >= 90" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "compliant"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] >= 90
      assert parsed["issues"] == []
    end

    test "minor_issues scenario has 1-2 issues with medium severity" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "minor_issues"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] >= 60 and parsed["compliance_score"] < 90
      assert length(parsed["issues"]) >= 1
    end

    test "major_issues scenario has high-severity issues + score < 50" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "major_issues"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] < 50
      assert Enum.any?(parsed["issues"], &(&1["severity"] == "high"))
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/mock_prompts_test.exs`
Expected: FAIL (module not loaded).

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/mock_prompts.ex`

```elixir
defmodule Showcase.Planogram.MockPrompts do
  @moduledoc """
  Canned scenarios registered on `AnthropicClient.Mock`. Three scenarios:
  `compliant`, `minor_issues`, `major_issues`.

  Each scenario returns a strict-JSON string matching the schema in
  `Impl.VisionRequest`'s system prompt.
  """

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.Planogram.Impl.VisionRequest

  @spec register_all() :: :ok
  def register_all do
    Mock.reset()

    for {scenario, text, usage} <- scenarios() do
      Mock.register(VisionRequest.fingerprint(),
        scenario: scenario,
        text: text,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cost_estimate_cents: usage.cost_estimate_cents
      )
    end

    :ok
  end

  defp scenarios do
    [
      {"compliant", compliant_json(), %{input_tokens: 2400, output_tokens: 380, cost_estimate_cents: 1.29}},
      {"minor_issues", minor_issues_json(), %{input_tokens: 2400, output_tokens: 520, cost_estimate_cents: 1.50}},
      {"major_issues", major_issues_json(), %{input_tokens: 2400, output_tokens: 700, cost_estimate_cents: 1.77}}
    ]
  end

  defp compliant_json do
    Jason.encode!(%{
      compliance_score: 96,
      executive_summary: "Shelf matches planogram. All rows compliant; product facings within tolerance.",
      rows: [
        %{name: "Top shelf", position: 1, status: "compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 6}], issues: []},
        %{name: "Middle shelf", position: 2, status: "compliant",
          found_products: [%{sku: "S2", name: "Sprite 500ml", qty: 5}, %{sku: "S3", name: "Fanta 500ml", qty: 4}], issues: []},
        %{name: "Bottom shelf", position: 3, status: "compliant",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}], issues: []}
      ],
      issues: [],
      unauthorized_items: [],
      suggestions: ["Shelf is in good state — no action needed."],
      photo_quality: %{score: 95, notes: "Sharp focus, good lighting."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 6},
        %{sku: "S2", name: "Sprite 500ml", qty: 5},
        %{sku: "S3", name: "Fanta 500ml", qty: 4},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end

  defp minor_issues_json do
    Jason.encode!(%{
      compliance_score: 78,
      executive_summary: "Shelf is mostly compliant. Two minor issues: Sprite is 1 facing under quota; Pepsi label is partially obscured.",
      rows: [
        %{name: "Top shelf", position: 1, status: "compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 6}], issues: []},
        %{name: "Middle shelf", position: 2, status: "partial",
          found_products: [%{sku: "S2", name: "Sprite 500ml", qty: 4}, %{sku: "S3", name: "Fanta 500ml", qty: 4}],
          issues: ["Sprite is 1 facing under quota (expected 5, found 4)."]},
        %{name: "Bottom shelf", position: 3, status: "partial",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}],
          issues: ["Pepsi label is partially obscured by promotional sticker."]}
      ],
      issues: [
        %{type: "wrong_qty", severity: "medium",
          description: "Sprite under-stocked on middle shelf (4 vs expected 5).",
          business_impact: "~10% lost facings → estimated 3-5% velocity drop on this SKU."},
        %{type: "photo_quality", severity: "low",
          description: "Promotional sticker partially covering Pepsi label on bottom shelf.",
          business_impact: "Cosmetic — does not affect compliance scoring."}
      ],
      unauthorized_items: [],
      suggestions: ["Restock 1 facing of Sprite 500ml on middle shelf.", "Remove or relocate the promotional sticker on bottom shelf."],
      photo_quality: %{score: 90, notes: "Good lighting, mild glare on bottom shelf."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 6},
        %{sku: "S2", name: "Sprite 500ml", qty: 4},
        %{sku: "S3", name: "Fanta 500ml", qty: 4},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end

  defp major_issues_json do
    Jason.encode!(%{
      compliance_score: 32,
      executive_summary: "Shelf is significantly non-compliant. Sprite missing entirely, unauthorized energy drinks on top shelf, Fanta short-stocked.",
      rows: [
        %{name: "Top shelf", position: 1, status: "non_compliant",
          found_products: [%{sku: "S1", name: "Coca-Cola 500ml", qty: 4}, %{sku: "X1", name: "Red Bull 250ml", qty: 3}],
          issues: ["Coca-Cola under-stocked (4 vs 6).", "Unauthorized: Red Bull 250ml not on planogram."]},
        %{name: "Middle shelf", position: 2, status: "non_compliant",
          found_products: [%{sku: "S3", name: "Fanta 500ml", qty: 2}],
          issues: ["Sprite 500ml MISSING (expected 5, found 0).", "Fanta short-stocked (2 vs 4)."]},
        %{name: "Bottom shelf", position: 3, status: "compliant",
          found_products: [%{sku: "S4", name: "Pepsi 500ml", qty: 6}], issues: []}
      ],
      issues: [
        %{type: "missing_product", severity: "high",
          description: "Sprite 500ml entirely missing from middle shelf (expected 5 facings).",
          business_impact: "Major — Sprite is a top-10 SKU; full out-of-stock event."},
        %{type: "unauthorized_item", severity: "high",
          description: "Red Bull 250ml present on top shelf — not on planogram for this store class.",
          business_impact: "Planogram drift; potential cannibalization of authorized SKUs."},
        %{type: "wrong_qty", severity: "medium",
          description: "Coca-Cola 500ml under-stocked (4 vs expected 6).",
          business_impact: "~33% facing loss on flagship SKU."},
        %{type: "wrong_qty", severity: "medium",
          description: "Fanta 500ml under-stocked (2 vs expected 4).",
          business_impact: "Visible gap; reduced category share-of-shelf."}
      ],
      unauthorized_items: [%{name: "Red Bull 250ml", row: 1}],
      suggestions: [
        "Immediate restock: 5 facings of Sprite 500ml on middle shelf.",
        "Remove Red Bull 250ml from top shelf — not authorized for this planogram.",
        "Restock 2 facings Coca-Cola 500ml + 2 facings Fanta 500ml."
      ],
      photo_quality: %{score: 88, notes: "Adequate."},
      extracted_products: [
        %{sku: "S1", name: "Coca-Cola 500ml", qty: 4},
        %{sku: "X1", name: "Red Bull 250ml", qty: 3},
        %{sku: "S3", name: "Fanta 500ml", qty: 2},
        %{sku: "S4", name: "Pepsi 500ml", qty: 6}
      ]
    })
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/mock_prompts_test.exs`
Expected: PASS — 4 assertions green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/mock_prompts.ex test/showcase/planogram/mock_prompts_test.exs
git commit -m "feat(planogram): MockPrompts with 3 scenarios (compliant / minor / major)"
```

---

### Task 6: VisionPipeline boundary (TDD)

**Files:**
- Create: `lib/showcase/planogram/vision_pipeline.ex`
- Test: `test/showcase/planogram/vision_pipeline_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/vision_pipeline_test.exs`

```elixir
defmodule Showcase.Planogram.VisionPipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram
  alias Showcase.Planogram.{Planogram, VerificationTask, VisionPipeline, MockPrompts}
  alias Showcase.Repo

  setup do
    MockPrompts.register_all()
    Phoenix.PubSub.subscribe(Showcase.PubSub, "planogram:task:*")
    :ok
  end

  describe "analyze/2" do
    test "compliant scenario: task transitions pending → analyzing → complete; result + usage persisted" do
      task = build_task("compliant")

      assert {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes())

      assert updated.status == "complete"
      assert updated.result["compliance_score"] >= 90
      assert updated.usage["input_tokens"] > 0
      assert updated.usage["cost_estimate_cents"] > 0
    end

    test "minor_issues scenario persists rich JSON" do
      task = build_task("minor_issues")
      {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes())

      assert updated.result["compliance_score"] >= 60 and updated.result["compliance_score"] < 90
      assert length(updated.result["issues"]) >= 1
    end

    test "missing photo file → task marked failed with error_reason" do
      task = build_task("compliant")

      assert {:error, _} = VisionPipeline.analyze(task, photo_bytes: nil)

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "failed"
      assert reloaded.error_reason =~ "no photo"
    end

    test "truncated mock JSON salvages via ResilientJSONParser and stays :complete with partial flag" do
      # Register a deliberately truncated response under a custom scenario
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "truncated",
        text: ~s|{"compliance_score": 75, "rows": [{"name": "Top", "po|,
        stop_reason: "max_tokens",
        input_tokens: 2000,
        output_tokens: 200
      )

      task = build_task("truncated")
      {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes(), max_tokens: 200)

      assert updated.status == "complete"
      assert updated.result["compliance_score"] == 75
      assert updated.result["_partial"] == true
    end
  end

  defp build_task(scenario) do
    {:ok, planogram} =
      Repo.insert(%Planogram{
        name: "test-planogram-#{System.unique_integer([:positive])}",
        reference_image_path: "/images/planogram/reference.png",
        expected_rows: %{
          "rows" => [
            %{"name" => "Top", "position" => 1,
              "products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]}
          ]
        }
      })

    {:ok, task} =
      Repo.insert(%VerificationTask{
        planogram_id: planogram.id,
        store_name: "Test Store",
        due_date: Date.utc_today(),
        mobile_token: random_token(),
        scenario: scenario,
        status: "pending",
        photo_path: "/uploads/planogram/test.png"
      })

    Map.put(task, :planogram, planogram)
  end

  defp png_bytes, do: <<137, 80, 78, 71, 13, 10, 26, 10>>
  defp random_token, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/vision_pipeline_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/vision_pipeline.ex`

```elixir
defmodule Showcase.Planogram.VisionPipeline do
  @moduledoc """
  Boundary module. Owns the single rich vision call:

      task (pending)
        → mark analyzing
        → read photo bytes
        → build VisionRequest
        → AnthropicClient.call
        → ResilientJSONParser.parse
        → persist result + usage, mark complete
        → broadcast {:planogram, :task_complete, task_id}

  Failures (no photo / Anthropic error) mark the task `failed` with an
  `error_reason` and broadcast `{:planogram, :task_failed, task_id, reason}`.
  """

  alias Showcase.Common.{AnthropicClient, ResilientJSONParser}
  alias Showcase.Planogram.{Planogram, VerificationTask, Impl.VisionRequest}
  alias Showcase.Repo

  require Logger

  @topic_prefix "planogram:task"

  @spec analyze(VerificationTask.t(), keyword()) ::
          {:ok, VerificationTask.t()} | {:error, term()}
  def analyze(%VerificationTask{} = task, opts) do
    photo_bytes = Keyword.get(opts, :photo_bytes)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    task = task |> Repo.preload(:planogram)

    with :ok <- ensure_photo(photo_bytes),
         {:ok, task} <- mark_analyzing(task),
         _ <- broadcast(task.id, {:planogram, :task_analyzing, task.id}),
         {:ok, raw_response} <- call_vision(task, photo_bytes, max_tokens),
         {:ok, decoded, partial?} <- parse_response(raw_response.text),
         {:ok, task} <- mark_complete(task, decoded, raw_response.usage, partial?) do
      broadcast(task.id, {:planogram, :task_complete, task.id})
      {:ok, task}
    else
      {:error, reason} = err ->
        Logger.error("VisionPipeline.analyze failed for task #{task.id}: #{inspect(reason)}")
        mark_failed(task, format_reason(reason))
        broadcast(task.id, {:planogram, :task_failed, task.id, format_reason(reason)})
        err
    end
  end

  defp ensure_photo(nil), do: {:error, :no_photo_attached}
  defp ensure_photo(bytes) when is_binary(bytes), do: :ok

  defp mark_analyzing(task) do
    task
    |> VerificationTask.changeset(%{status: "analyzing"})
    |> Repo.update()
  end

  defp call_vision(task, photo_bytes, max_tokens) do
    planogram = %{
      name: task.planogram.name,
      expected_rows: task.planogram.expected_rows
    }

    request =
      VisionRequest.build(planogram, photo_bytes,
        scenario: task.scenario,
        max_tokens: max_tokens
      )

    AnthropicClient.call(request)
  end

  defp parse_response(text) do
    case ResilientJSONParser.parse(text) do
      {:ok, decoded} -> {:ok, decoded, false}
      {:partial, decoded} -> {:ok, Map.put(decoded, "_partial", true), true}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end

  defp mark_complete(task, decoded, usage, _partial?) do
    task
    |> VerificationTask.changeset(%{
      status: "complete",
      result: decoded,
      usage: %{
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "cost_estimate_cents" => usage.cost_estimate_cents
      }
    })
    |> Repo.update()
  end

  defp mark_failed(task, reason) do
    task
    |> VerificationTask.changeset(%{status: "failed", error_reason: reason})
    |> Repo.update()
  end

  defp format_reason({:parse_failed, r}), do: "parse failed: #{inspect(r)}"
  defp format_reason(:no_photo_attached), do: "no photo attached"
  defp format_reason(other), do: inspect(other)

  defp broadcast(task_id, msg) do
    Phoenix.PubSub.broadcast(Showcase.PubSub, "#{@topic_prefix}:#{task_id}", msg)
  end

  @doc "Public topic name for a task, exposed for LiveViews to subscribe."
  @spec topic(integer()) :: String.t()
  def topic(task_id), do: "#{@topic_prefix}:#{task_id}"
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/vision_pipeline_test.exs`
Expected: PASS — all 4 assertions green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/vision_pipeline.ex test/showcase/planogram/vision_pipeline_test.exs
git commit -m "feat(planogram): VisionPipeline boundary with status transitions + ResilientJSONParser salvage"
```

---

### Task 7: Oban Worker (TDD)

**Files:**
- Create: `lib/showcase/planogram/worker.ex`
- Test: `test/showcase/planogram/worker_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/worker_test.exs`

```elixir
defmodule Showcase.Planogram.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Planogram.{Planogram, VerificationTask, Worker, MockPrompts}
  alias Showcase.Repo

  setup do
    MockPrompts.register_all()
    :ok
  end

  describe "perform/1" do
    test "loads task, reads bundled photo from priv/static, runs VisionPipeline, marks complete" do
      {:ok, planogram} =
        Repo.insert(%Planogram{
          name: "worker-pg-#{System.unique_integer([:positive])}",
          reference_image_path: "/images/planogram/reference.png",
          expected_rows: %{"rows" => []}
        })

      {:ok, task} =
        Repo.insert(%VerificationTask{
          planogram_id: planogram.id,
          store_name: "Worker Test",
          due_date: Date.utc_today(),
          mobile_token: "wt-#{System.unique_integer([:positive])}",
          scenario: "compliant",
          status: "pending",
          # Worker reads bundled photo by scenario when photo_path is nil
          photo_path: nil
        })

      assert :ok = perform_job(Worker, %{"task_id" => task.id})

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "complete"
      assert reloaded.result["compliance_score"] >= 90
    end

    test "honors :max_tokens override in args (used by force-truncation demo)" do
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "compliant",
        text: ~s|{"compliance_score": 80, "rows": [{"name": "Top|,
        stop_reason: "max_tokens",
        input_tokens: 100,
        output_tokens: 50
      )

      {:ok, planogram} = Repo.insert(%Planogram{
        name: "max-tokens-pg",
        reference_image_path: "/images/planogram/reference.png",
        expected_rows: %{"rows" => []}
      })

      {:ok, task} = Repo.insert(%VerificationTask{
        planogram_id: planogram.id,
        store_name: "Truncation Test",
        due_date: Date.utc_today(),
        mobile_token: "trunc-#{System.unique_integer([:positive])}",
        scenario: "compliant",
        photo_path: nil
      })

      assert :ok = perform_job(Worker, %{"task_id" => task.id, "max_tokens" => 200})

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "complete"
      assert reloaded.result["_partial"] == true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/worker_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/worker.ex`

```elixir
defmodule Showcase.Planogram.Worker do
  @moduledoc """
  Oban worker for the planogram vision pipeline.

  Args: `%{"task_id" => integer, "max_tokens" => integer (optional)}`.

  Reads the photo bytes from disk (either from the uploaded path or a
  bundled scenario fallback under `priv/static/images/planogram/`) and
  hands off to `VisionPipeline.analyze/2`.
  """

  use Oban.Worker, queue: :planogram, max_attempts: 3

  alias Showcase.Planogram.{VerificationTask, VisionPipeline}
  alias Showcase.Repo

  @bundled_dir "priv/static/images/planogram"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id} = args}) do
    case Repo.get(VerificationTask, task_id) do
      nil ->
        {:error, :task_not_found}

      task ->
        photo_bytes = read_photo(task)
        max_tokens = Map.get(args, "max_tokens", 4096)

        case VisionPipeline.analyze(task, photo_bytes: photo_bytes, max_tokens: max_tokens) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
          # NB: pipeline already marked the task failed and broadcast — Oban
          # should NOT retry on parse/no-photo errors. We swallow the {:error}
          # to keep Oban from re-running. (Anthropic transport errors *do* go
          # via Oban retry because they manifest before the pipeline marks
          # the task `analyzing`.)
        end
    end
  end

  defp read_photo(%VerificationTask{photo_path: "/uploads/" <> _ = path}) do
    File.read!(Path.join("priv/static", path))
  end

  defp read_photo(%VerificationTask{photo_path: path}) when is_binary(path) do
    File.read!(Path.join("priv/static", String.trim_leading(path, "/")))
  rescue
    _ -> bundled_fallback(nil)
  end

  defp read_photo(%VerificationTask{photo_path: nil, scenario: scenario}) do
    bundled_fallback(scenario)
  end

  defp bundled_fallback(scenario) do
    filename =
      case scenario do
        "compliant" -> "captured_compliant.png"
        "minor_issues" -> "captured_minor_issues.png"
        "major_issues" -> "captured_major_issues.png"
        _ -> "captured_compliant.png"
      end

    path = Path.join(@bundled_dir, filename)

    case File.read(path) do
      {:ok, bytes} -> bytes
      # Fallback to a 1-byte PNG header so the pipeline still runs in CI
      # before the bundled images are committed.
      {:error, _} -> <<137, 80, 78, 71, 13, 10, 26, 10>>
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/worker_test.exs`
Expected: PASS — 2 assertions green.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/worker.ex test/showcase/planogram/worker_test.exs
git commit -m "feat(planogram): Oban worker reading photo from disk + bundled fallbacks"
```

---

### Task 8: MobileHandoff boundary (TDD)

**Files:**
- Create: `lib/showcase/planogram/mobile_handoff.ex`
- Test: `test/showcase/planogram/mobile_handoff_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/mobile_handoff_test.exs`

```elixir
defmodule Showcase.Planogram.MobileHandoffTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram.{Planogram, VerificationTask, MobileHandoff}
  alias Showcase.Repo

  setup do
    File.rm_rf!("priv/static/uploads/planogram")
    File.mkdir_p!("priv/static/uploads/planogram")
    :ok
  end

  describe "generate_token/0" do
    test "produces unique URL-safe tokens" do
      t1 = MobileHandoff.generate_token()
      t2 = MobileHandoff.generate_token()

      refute t1 == t2
      assert byte_size(t1) >= 16
      assert t1 == URI.encode(t1)
    end
  end

  describe "find_task_by_token/1" do
    test "finds an open task by mobile_token" do
      task = insert_task(status: "pending")
      assert {:ok, found} = MobileHandoff.find_task_by_token(task.mobile_token)
      assert found.id == task.id
    end

    test "returns :not_found for unknown token" do
      assert {:error, :not_found} = MobileHandoff.find_task_by_token("nope-#{System.unique_integer()}")
    end

    test "refuses tokens for tasks already complete or failed" do
      task = insert_task(status: "complete")
      assert {:error, :already_processed} = MobileHandoff.find_task_by_token(task.mobile_token)
    end
  end

  describe "finalize_upload/2" do
    test "writes photo bytes to priv/static/uploads/planogram and updates task.photo_path" do
      task = insert_task(status: "pending")
      bytes = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0>>

      assert {:ok, updated} = MobileHandoff.finalize_upload(task, bytes)
      assert updated.photo_path =~ "/uploads/planogram/"
      assert updated.photo_path =~ ".png"

      on_disk = File.read!(Path.join("priv/static", updated.photo_path))
      assert on_disk == bytes
    end
  end

  defp insert_task(opts) do
    {:ok, pg} = Repo.insert(%Planogram{
      name: "handoff-pg-#{System.unique_integer([:positive])}",
      reference_image_path: "/images/planogram/reference.png",
      expected_rows: %{"rows" => []}
    })

    {:ok, task} = Repo.insert(%VerificationTask{
      planogram_id: pg.id,
      store_name: "Handoff Test",
      due_date: Date.utc_today(),
      mobile_token: MobileHandoff.generate_token(),
      scenario: "compliant",
      status: Keyword.get(opts, :status, "pending")
    })

    task
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/planogram/mobile_handoff_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/planogram/mobile_handoff.ex`

```elixir
defmodule Showcase.Planogram.MobileHandoff do
  @moduledoc """
  Coordinates the desktop ↔ phone handoff flow.

  Lifecycle:
    1. Manager creates a task → `generate_token/0` assigns it a URL-safe
       random token (also written to DB at insert time).
    2. Merchandiser view renders a QR encoding `/planogram/mobile/<token>`.
    3. Phone scans, hits `MobileCaptureLive`, uploads a photo.
    4. `finalize_upload/2` writes the bytes to `priv/static/uploads/planogram/`
       and stores the relative path in `task.photo_path`.
    5. Desktop's PubSub subscription notices the photo is in place and
       enables the "Run analysis" button.
  """

  alias Showcase.Planogram.VerificationTask
  alias Showcase.Repo

  @upload_dir "priv/static/uploads/planogram"

  @spec generate_token() :: String.t()
  def generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @spec find_task_by_token(String.t()) ::
          {:ok, VerificationTask.t()} | {:error, :not_found | :already_processed}
  def find_task_by_token(token) when is_binary(token) do
    case Repo.get_by(VerificationTask, mobile_token: token) do
      nil ->
        {:error, :not_found}

      %VerificationTask{status: s} when s in ["complete", "failed"] ->
        {:error, :already_processed}

      task ->
        {:ok, task}
    end
  end

  @spec finalize_upload(VerificationTask.t(), binary()) ::
          {:ok, VerificationTask.t()} | {:error, term()}
  def finalize_upload(%VerificationTask{} = task, bytes) when is_binary(bytes) do
    File.mkdir_p!(@upload_dir)
    extension = if String.starts_with?(bytes, <<137, 80, 78, 71>>), do: ".png", else: ".jpg"
    filename = "#{task.id}-#{System.unique_integer([:positive])}#{extension}"
    full_path = Path.join(@upload_dir, filename)
    File.write!(full_path, bytes)

    relative = "/uploads/planogram/#{filename}"

    task
    |> VerificationTask.changeset(%{photo_path: relative})
    |> Repo.update()
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/planogram/mobile_handoff_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/planogram/mobile_handoff.ex test/showcase/planogram/mobile_handoff_test.exs
git commit -m "feat(planogram): MobileHandoff boundary — token gen + photo upload finalize"
```

---

### Task 9: Public context + Seed (TDD on Seed)

**Files:**
- Create: `lib/showcase/planogram.ex`
- Create: `lib/showcase/planogram/seed.ex`
- Create: `priv/static/images/planogram/` (with 4 placeholder PNGs — see Step 2)
- Test: `test/showcase/planogram/seed_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase/planogram/seed_test.exs`

```elixir
defmodule Showcase.Planogram.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram.{Planogram, VerificationTask, Seed}
  alias Showcase.Repo
  import Ecto.Query

  describe "DemoSeeder contract" do
    test "name/0 returns 'Planogram Manager'" do
      assert Seed.name() == "Planogram Manager"
    end

    test "description/0 returns a non-empty string" do
      assert is_binary(Seed.description())
      assert String.length(Seed.description()) > 20
    end

    test "tables/0 lists the pg_ tables in dependency-aware order" do
      assert Seed.tables() == ["pg_verification_tasks", "pg_planograms"]
    end

    test "oban_queue/0 returns :planogram" do
      assert Seed.oban_queue() == :planogram
    end
  end

  describe "seed/0" do
    test "creates 1 planogram + 3 tasks with distinct scenarios" do
      :ok = Seed.seed()

      planograms = Repo.all(Planogram)
      assert length(planograms) >= 1

      tasks = Repo.all(from t in VerificationTask, order_by: t.id)
      assert length(tasks) == 3
      scenarios = Enum.map(tasks, & &1.scenario) |> Enum.sort()
      assert scenarios == ["compliant", "major_issues", "minor_issues"]

      # Each task has a unique mobile_token
      tokens = Enum.map(tasks, & &1.mobile_token)
      assert length(Enum.uniq(tokens)) == 3

      # One task has due_date in the past (for overdue demo)
      today = Date.utc_today()
      assert Enum.any?(tasks, &(Date.compare(&1.due_date, today) == :lt))
    end

    test "is idempotent" do
      :ok = Seed.seed()
      first_count = Repo.aggregate(VerificationTask, :count)
      :ok = Seed.seed()
      assert Repo.aggregate(VerificationTask, :count) == first_count
    end
  end
end
```

- [ ] **Step 2: Create bundled image placeholders**

Each of these is a tiny valid PNG (1×1 transparent pixel, the smallest valid PNG). Bash-create them with:

```bash
mkdir -p priv/static/images/planogram

# Smallest valid PNG: 67 bytes, 1×1 transparent
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' \
  | tee priv/static/images/planogram/reference_3-shelf-snacks.png \
        priv/static/images/planogram/captured_compliant.png \
        priv/static/images/planogram/captured_minor_issues.png \
        priv/static/images/planogram/captured_major_issues.png > /dev/null
```

These are deliberately tiny placeholders — real demo photos can replace them later in Phase 7 (polish). What matters now is that the bytes are stable, the PNG magic header is correct (so `media_type/1` returns `image/png`), and CI runs without binary missing.

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/showcase/planogram/seed_test.exs`
Expected: FAIL — modules not loaded.

- [ ] **Step 4: Write the context module**

File: `lib/showcase/planogram.ex`

```elixir
defmodule Showcase.Planogram do
  @moduledoc """
  Public boundary for the Planogram Manager demo.

  Read paths (list_tasks, get_task, list_planograms) are plain Ecto.
  Write paths that enqueue Oban jobs (enqueue_analysis/1) live here.
  """

  import Ecto.Query

  alias Showcase.Planogram.{Planogram, VerificationTask, Worker, Impl.Overdue}
  alias Showcase.Repo

  @spec list_tasks() :: list(VerificationTask.t())
  def list_tasks do
    from(t in VerificationTask, preload: [:planogram], order_by: [asc: t.due_date])
    |> Repo.all()
  end

  @spec get_task!(integer()) :: VerificationTask.t()
  def get_task!(id) do
    VerificationTask
    |> Repo.get!(id)
    |> Repo.preload(:planogram)
  end

  @spec list_planograms() :: list(Planogram.t())
  def list_planograms do
    Repo.all(from p in Planogram, order_by: [asc: p.name])
  end

  @spec bucket_tasks(Date.t()) :: map()
  def bucket_tasks(today \\ Date.utc_today()) do
    list_tasks() |> Overdue.bucket(today)
  end

  @doc """
  Enqueue an analysis job for the given task. Optional `:max_tokens` for
  the force-truncation demo.
  """
  @spec enqueue_analysis(integer(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_analysis(task_id, opts \\ []) do
    args = %{"task_id" => task_id}

    args =
      case Keyword.get(opts, :max_tokens) do
        nil -> args
        n when is_integer(n) -> Map.put(args, "max_tokens", n)
      end

    args |> Worker.new() |> Oban.insert()
  end

  @doc """
  Create a manager-authored task. Used by the Manager view.
  """
  @spec create_task(map()) :: {:ok, VerificationTask.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    attrs =
      attrs
      |> Map.put_new("mobile_token", Showcase.Planogram.MobileHandoff.generate_token())
      |> Map.put_new("status", "pending")

    %VerificationTask{}
    |> VerificationTask.changeset(attrs)
    |> Repo.insert()
  end
end
```

- [ ] **Step 5: Write the Seed module**

File: `lib/showcase/planogram/seed.ex`

```elixir
defmodule Showcase.Planogram.Seed do
  @moduledoc """
  Seeds 1 planogram (3-shelf snack display) + 3 verification tasks, one
  per scenario, with mixed due-dates to demonstrate Today / Tomorrow /
  Overdue bucketing.

  Idempotent: re-running yields the same baseline state.
  """

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.Planogram.{Planogram, VerificationTask, MobileHandoff}
  alias Showcase.Repo

  @impl true
  def name, do: "Planogram Manager"

  @impl true
  def description do
    "Retail shelf compliance via a single vision call. The system returns score, per-row breakdown, issues, and suggestions — in seconds, not afternoons."
  end

  @impl true
  def tables, do: ~w(pg_verification_tasks pg_planograms)

  @impl true
  def oban_queue, do: :planogram

  @impl true
  def seed do
    Repo.transaction(fn ->
      planogram = upsert_planogram()
      upsert_tasks(planogram)
    end)

    :ok
  end

  defp upsert_planogram do
    case Repo.get_by(Planogram, name: "3-shelf snack display") do
      nil ->
        {:ok, pg} =
          Repo.insert(%Planogram{
            name: "3-shelf snack display",
            description: "Standard 3-shelf endcap for soft drinks. Top: Coca-Cola. Middle: Sprite + Fanta. Bottom: Pepsi.",
            reference_image_path: "/images/planogram/reference_3-shelf-snacks.png",
            expected_rows: %{
              "rows" => [
                %{"name" => "Top shelf", "position" => 1,
                  "products" => [%{"sku" => "S1", "name" => "Coca-Cola 500ml", "qty" => 6}]},
                %{"name" => "Middle shelf", "position" => 2,
                  "products" => [
                    %{"sku" => "S2", "name" => "Sprite 500ml", "qty" => 5},
                    %{"sku" => "S3", "name" => "Fanta 500ml", "qty" => 4}
                  ]},
                %{"name" => "Bottom shelf", "position" => 3,
                  "products" => [%{"sku" => "S4", "name" => "Pepsi 500ml", "qty" => 6}]}
              ]
            }
          })

        pg

      existing ->
        existing
    end
  end

  defp upsert_tasks(planogram) do
    today = Date.utc_today()

    [
      %{store_name: "Downtown Mart", scenario: "compliant", due_date: today},
      %{store_name: "Westside Express", scenario: "minor_issues", due_date: Date.add(today, 1)},
      %{store_name: "Eastpark Grocery", scenario: "major_issues", due_date: Date.add(today, -2)}
    ]
    |> Enum.each(fn task_attrs ->
      case Repo.get_by(VerificationTask, store_name: task_attrs.store_name, planogram_id: planogram.id) do
        nil ->
          Repo.insert!(%VerificationTask{
            planogram_id: planogram.id,
            store_name: task_attrs.store_name,
            due_date: task_attrs.due_date,
            scenario: task_attrs.scenario,
            mobile_token: MobileHandoff.generate_token(),
            status: "pending"
          })

        _existing ->
          :ok
      end
    end)
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/showcase/planogram/seed_test.exs`
Expected: PASS — all assertions green.

- [ ] **Step 7: Run the seed against dev DB**

Run: `mix run -e "Showcase.Planogram.Seed.seed()"`
Expected: no errors. Check via `psql showcase_dev -c "SELECT id, store_name, scenario, due_date FROM pg_verification_tasks;"` — 3 rows.

- [ ] **Step 8: Commit**

```bash
git add lib/showcase/planogram.ex lib/showcase/planogram/seed.ex \
        priv/static/images/planogram/ \
        test/showcase/planogram/seed_test.exs
git commit -m "feat(planogram): public context + Seed (1 planogram + 3 tasks) + bundled image placeholders"
```

---

### Task 10: PlanogramLive — role switcher + Merchandiser view (TDD)

**Files:**
- Create: `lib/showcase_web/live/planogram/planogram_live.ex`
- Create: `lib/showcase_web/live/planogram/components/qr_handoff.ex`
- Modify: `lib/showcase_web/router.ex` (add routes)
- Test: `test/showcase_web/live/planogram/planogram_live_test.exs`

- [ ] **Step 1: Add routes**

Open `lib/showcase_web/router.ex`. In the existing `scope "/"` (browser pipeline), add:

```elixir
live "/planogram", Planogram.PlanogramLive, :merchandiser
live "/planogram/mobile/:token", Planogram.MobileCaptureLive, :capture
```

- [ ] **Step 2: Write the failing test**

File: `test/showcase_web/live/planogram/planogram_live_test.exs`

```elixir
defmodule ShowcaseWeb.Planogram.PlanogramLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Showcase.Planogram.{Seed, MockPrompts}

  setup do
    Seed.seed()
    MockPrompts.register_all()
    :ok
  end

  describe "merchandiser view (default)" do
    test "renders the role switcher and Merchandiser headline", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/planogram")
      assert html =~ "Merchandiser"
      assert html =~ "Today"
      assert html =~ "Overdue"
    end

    test "lists 3 seeded tasks bucketed by due date", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      rendered = render(view)
      assert rendered =~ "Downtown Mart"
      assert rendered =~ "Westside Express"
      assert rendered =~ "Eastpark Grocery"
    end

    test "switches role to Manager via phx-click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      assert view |> element("button", "Manager") |> render_click() =~ "Author planograms"
    end

    test "Run analysis enqueues an Oban job", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      # Pick the first task's "Run analysis" button
      view |> element("button[phx-click='run_analysis']", "Run analysis") |> render_click()
      assert_enqueued worker: Showcase.Planogram.Worker
    end
  end

  describe "QR handoff" do
    test "renders an SVG QR code for the active task", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Open on phone") |> render_click()
      rendered = render(view)
      assert rendered =~ "<svg"
      assert rendered =~ "/planogram/mobile/"
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/showcase_web/live/planogram/planogram_live_test.exs`
Expected: FAIL — LiveView not defined.

- [ ] **Step 4: Write the QR component**

File: `lib/showcase_web/live/planogram/components/qr_handoff.ex`

```elixir
defmodule ShowcaseWeb.Planogram.Components.QRHandoff do
  use Phoenix.Component

  attr :url, :string, required: true
  attr :size, :integer, default: 240

  def qr_handoff(assigns) do
    matrix = EQRCode.encode(assigns.url)
    svg = EQRCode.svg(matrix, viewbox: true, width: assigns.size)
    assigns = assign(assigns, :svg, svg)

    ~H"""
    <div class="inline-block rounded border bg-white p-3">
      <div class="mb-2 text-xs uppercase tracking-wide text-zinc-500">
        Open on phone
      </div>
      <%= Phoenix.HTML.raw(@svg) %>
      <div class="mt-2 break-all text-xs text-zinc-400"><%= @url %></div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Write the LiveView (Merchandiser view + role chrome only)**

File: `lib/showcase_web/live/planogram/planogram_live.ex`

```elixir
defmodule ShowcaseWeb.Planogram.PlanogramLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.VerificationTask
  alias ShowcaseWeb.Planogram.Components.QRHandoff

  import QRHandoff

  @roles ~w(merchandiser manager admin)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all current tasks' progress
      for task <- Planogram.list_tasks() do
        Phoenix.PubSub.subscribe(Showcase.PubSub, Showcase.Planogram.VisionPipeline.topic(task.id))
      end
    end

    {:ok,
     socket
     |> assign(:role, "merchandiser")
     |> assign(:active_qr_task_id, nil)
     |> load_tasks()}
  end

  defp load_tasks(socket) do
    today = Date.utc_today()
    buckets = Planogram.bucket_tasks(today)
    assign(socket, buckets: buckets, today: today)
  end

  @impl true
  def handle_event("switch_role", %{"role" => role}, socket) when role in @roles do
    {:noreply, assign(socket, role: role)}
  end

  def handle_event("run_analysis", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    Planogram.enqueue_analysis(id)
    {:noreply, socket |> put_flash(:info, "Analysis enqueued.") |> load_tasks()}
  end

  def handle_event("force_truncation", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    Planogram.enqueue_analysis(id, max_tokens: 200)
    {:noreply, socket |> put_flash(:info, "Truncated analysis enqueued (max_tokens=200).") |> load_tasks()}
  end

  def handle_event("toggle_qr", %{"task_id" => task_id}, socket) do
    {id, _} = Integer.parse(task_id)
    new_active = if socket.assigns.active_qr_task_id == id, do: nil, else: id
    {:noreply, assign(socket, active_qr_task_id: new_active)}
  end

  @impl true
  def handle_info({:planogram, _phase, _task_id}, socket) do
    {:noreply, load_tasks(socket)}
  end

  def handle_info({:planogram, :task_failed, _task_id, _reason}, socket) do
    {:noreply, load_tasks(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Planogram Manager</h1>
            <p class="text-sm text-zinc-500 mt-1">
              <%= role_subtitle(@role) %>
            </p>
          </div>
          <div class="flex gap-2 items-center">
            <%= for role <- ~w(merchandiser manager admin) do %>
              <button type="button"
                      phx-click="switch_role"
                      phx-value-role={role}
                      class={[
                        "rounded px-3 py-2 text-sm font-medium",
                        if(@role == role, do: "bg-zinc-900 text-white", else: "bg-white border text-zinc-700 hover:bg-zinc-100")
                      ]}>
                <%= String.capitalize(role) %>
              </button>
            <% end %>
            <a href="/" class="ml-2 text-sm text-zinc-500 underline">&larr; Dashboard</a>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-6">
        <%= case @role do %>
          <% "merchandiser" -> %>
            <.render_merchandiser buckets={@buckets} active_qr_task_id={@active_qr_task_id} />
          <% "manager" -> %>
            <.render_manager />
          <% "admin" -> %>
            <.render_admin />
        <% end %>
      </main>
    </div>
    """
  end

  defp role_subtitle("merchandiser"), do: "Today's audits — capture photo, run AI compliance check."
  defp role_subtitle("manager"), do: "Author planograms and create verification tasks."
  defp role_subtitle("admin"), do: "Audit log, model settings, cost overview."

  attr :buckets, :map, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp render_merchandiser(assigns) do
    ~H"""
    <div class="space-y-6">
      <.task_bucket label="Overdue" tasks={@buckets.overdue} tone="rose" active_qr_task_id={@active_qr_task_id} />
      <.task_bucket label="Today" tasks={@buckets.today} tone="emerald" active_qr_task_id={@active_qr_task_id} />
      <.task_bucket label="Tomorrow" tasks={@buckets.tomorrow} tone="amber" active_qr_task_id={@active_qr_task_id} />
      <.task_bucket label="Later" tasks={@buckets.later} tone="zinc" active_qr_task_id={@active_qr_task_id} />
      <.task_bucket label="Done" tasks={@buckets.done} tone="zinc" active_qr_task_id={@active_qr_task_id} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tasks, :list, required: true
  attr :tone, :string, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp task_bucket(assigns) do
    ~H"""
    <section :if={@tasks != []} class="rounded border bg-white">
      <header class={["border-b px-4 py-2 text-xs uppercase tracking-wide",
                      "text-#{@tone}-700 bg-#{@tone}-50"]}>
        <%= @label %> (<%= length(@tasks) %>)
      </header>
      <ul class="divide-y">
        <%= for task <- @tasks do %>
          <li class="p-4">
            <.task_row task={task} active_qr_task_id={@active_qr_task_id} />
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  attr :task, VerificationTask, required: true
  attr :active_qr_task_id, :integer, default: nil

  defp task_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <div class="flex-1">
        <div class="flex items-center gap-3">
          <a href={~p"/planogram/#{@task.id}"} class="font-medium hover:underline">
            <%= @task.store_name %>
          </a>
          <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
            <%= @task.status %>
          </span>
        </div>
        <div class="text-xs text-zinc-500 mt-1">
          Due <%= Date.to_iso8601(@task.due_date) %>
          · <%= @task.planogram && @task.planogram.name %>
          · scenario: <%= @task.scenario %>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <button type="button"
                phx-click="run_analysis"
                phx-value-task_id={@task.id}
                disabled={@task.status in ["analyzing", "complete"]}
                class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-40">
          Run analysis
        </button>
        <button type="button"
                phx-click="force_truncation"
                phx-value-task_id={@task.id}
                title="Cap max_tokens=200 to demo the resilient parser"
                class="rounded border px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100">
          Force truncation
        </button>
        <button type="button"
                phx-click="toggle_qr"
                phx-value-task_id={@task.id}
                class="rounded border px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100">
          <%= if @active_qr_task_id == @task.id, do: "Hide QR", else: "Open on phone" %>
        </button>
      </div>
    </div>

    <div :if={@active_qr_task_id == @task.id} class="mt-4">
      <.qr_handoff url={qr_url(@task)} />
    </div>
    """
  end

  defp qr_url(task) do
    host = ShowcaseWeb.Endpoint.config(:url)[:host] || "localhost"
    port = ShowcaseWeb.Endpoint.config(:http)[:port] || 4321
    "http://#{host}:#{port}/planogram/mobile/#{task.mobile_token}"
  end

  defp status_classes("pending"), do: "bg-zinc-100 text-zinc-700"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-zinc-100"

  defp render_manager(assigns) do
    ~H"""
    <section class="rounded border bg-white p-4">
      <h2 class="text-lg font-medium mb-2">Author planograms</h2>
      <p class="text-sm text-zinc-500">
        Planogram authoring + task creation lands in Task 11.
        (Roles already wired; this panel is a placeholder so the role switcher works.)
      </p>
    </section>
    """
  end

  defp render_admin(assigns) do
    ~H"""
    <section class="rounded border bg-white p-4">
      <h2 class="text-lg font-medium mb-2">Admin overview</h2>
      <p class="text-sm text-zinc-500">
        Audit log + model selection + cost overview lands in Task 11.
      </p>
    </section>
    """
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/showcase_web/live/planogram/planogram_live_test.exs`
Expected: PASS — 5 assertions green.

- [ ] **Step 7: Commit**

```bash
git add lib/showcase_web/live/planogram/ lib/showcase_web/router.ex \
        test/showcase_web/live/planogram/planogram_live_test.exs
git commit -m "feat(planogram): PlanogramLive with role switcher + Merchandiser view + QR handoff"
```

---

### Task 11: PlanogramLive — Manager + Admin views (panel-only; no new routes)

**Files:**
- Modify: `lib/showcase_web/live/planogram/planogram_live.ex`

- [ ] **Step 1: Write the failing test (append to existing test file)**

Append to `test/showcase_web/live/planogram/planogram_live_test.exs`:

```elixir
  describe "manager view" do
    test "lists existing planograms + create-task form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Manager") |> render_click()
      rendered = render(view)
      assert rendered =~ "3-shelf snack display"
      assert rendered =~ "Create task"
    end

    test "create_task inserts a new VerificationTask", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Manager") |> render_click()

      before_count = Showcase.Repo.aggregate(Showcase.Planogram.VerificationTask, :count)

      view
      |> form("form[phx-submit='create_task']",
        %{
          "task" => %{
            "store_name" => "New Test Store",
            "due_date" => Date.to_iso8601(Date.utc_today()),
            "planogram_id" => first_planogram_id(),
            "scenario" => "compliant"
          }
        })
      |> render_submit()

      after_count = Showcase.Repo.aggregate(Showcase.Planogram.VerificationTask, :count)
      assert after_count == before_count + 1
    end

    defp first_planogram_id do
      [pg | _] = Showcase.Repo.all(Showcase.Planogram.Planogram)
      pg.id
    end
  end

  describe "admin view" do
    test "shows model and prompt summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/planogram")
      view |> element("button", "Admin") |> render_click()
      rendered = render(view)
      assert rendered =~ "claude-sonnet-4-5"
      assert rendered =~ "Active model"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase_web/live/planogram/planogram_live_test.exs`
Expected: FAIL — Manager form / Admin summary missing.

- [ ] **Step 3: Replace `render_manager` and `render_admin` in PlanogramLive**

In `lib/showcase_web/live/planogram/planogram_live.ex`:

Add the planograms assign to `mount/3`:

```elixir
{:ok,
 socket
 |> assign(:role, "merchandiser")
 |> assign(:active_qr_task_id, nil)
 |> assign(:planograms, Planogram.list_planograms())
 |> load_tasks()}
```

Add the `create_task` handler near the other handlers:

```elixir
def handle_event("create_task", %{"task" => task_attrs}, socket) do
  case Planogram.create_task(task_attrs) do
    {:ok, _task} ->
      {:noreply,
       socket
       |> put_flash(:info, "Task created.")
       |> assign(:planograms, Planogram.list_planograms())
       |> load_tasks()}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Could not create task.")}
  end
end
```

Replace `render_manager/1` with:

```elixir
defp render_manager(assigns) do
  ~H"""
  <div class="grid grid-cols-2 gap-6">
    <section class="rounded border bg-white p-4">
      <h2 class="text-lg font-medium mb-3">Existing planograms</h2>
      <ul class="divide-y">
        <li :for={pg <- @planograms} class="py-2">
          <div class="font-medium"><%= pg.name %></div>
          <div class="text-xs text-zinc-500"><%= pg.description %></div>
        </li>
      </ul>
    </section>

    <section class="rounded border bg-white p-4">
      <h2 class="text-lg font-medium mb-3">Create task</h2>
      <form phx-submit="create_task" class="space-y-3">
        <div>
          <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Store</label>
          <input name="task[store_name]" required class="w-full rounded border px-3 py-2" />
        </div>
        <div>
          <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Planogram</label>
          <select name="task[planogram_id]" class="w-full rounded border px-3 py-2">
            <option :for={pg <- @planograms} value={pg.id}><%= pg.name %></option>
          </select>
        </div>
        <div>
          <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Due date</label>
          <input name="task[due_date]" type="date" required class="w-full rounded border px-3 py-2" />
          <p class="mt-1 text-xs text-zinc-400">Past dates allowed (demo overdue treatment).</p>
        </div>
        <div>
          <label class="block text-xs uppercase tracking-wide text-zinc-500 mb-1">Scenario</label>
          <select name="task[scenario]" class="w-full rounded border px-3 py-2">
            <option value="compliant">compliant</option>
            <option value="minor_issues">minor_issues</option>
            <option value="major_issues">major_issues</option>
          </select>
        </div>
        <button type="submit"
                class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700">
          Create task
        </button>
      </form>
    </section>
  </div>
  """
end
```

Replace `render_admin/1` with:

```elixir
defp render_admin(assigns) do
  ~H"""
  <section class="rounded border bg-white p-4">
    <h2 class="text-lg font-medium mb-3">Admin overview</h2>
    <dl class="grid grid-cols-2 gap-4 text-sm">
      <div>
        <dt class="text-xs uppercase tracking-wide text-zinc-500">Active model</dt>
        <dd class="font-mono">claude-sonnet-4-5</dd>
      </div>
      <div>
        <dt class="text-xs uppercase tracking-wide text-zinc-500">Oban queue</dt>
        <dd class="font-mono">:planogram (concurrency 5)</dd>
      </div>
      <div>
        <dt class="text-xs uppercase tracking-wide text-zinc-500">Fingerprint</dt>
        <dd class="font-mono">planogram_vision_v1</dd>
      </div>
      <div>
        <dt class="text-xs uppercase tracking-wide text-zinc-500">Scenarios</dt>
        <dd class="font-mono">compliant / minor_issues / major_issues</dd>
      </div>
    </dl>
    <p class="mt-4 text-xs text-zinc-500">
      Reset all data and audit log via <a href="/admin/reset" class="underline">/admin/reset</a>.
    </p>
  </section>
  """
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase_web/live/planogram/planogram_live_test.exs`
Expected: PASS — all assertions green (5 from Task 10 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add lib/showcase_web/live/planogram/planogram_live.ex \
        test/showcase_web/live/planogram/planogram_live_test.exs
git commit -m "feat(planogram): Manager (create-task form) + Admin (model overview) views"
```

---

### Task 12: PlanogramLive — task detail with result render (TDD)

**Files:**
- Create: `lib/showcase_web/live/planogram/task_detail_live.ex`
- Create: `lib/showcase_web/live/planogram/components/compliance_gauge.ex`
- Create: `lib/showcase_web/live/planogram/components/per_row_table.ex`
- Modify: `lib/showcase_web/router.ex` (add task detail route)
- Test: `test/showcase_web/live/planogram/task_detail_live_test.exs`

- [ ] **Step 1: Add route**

In `lib/showcase_web/router.ex`, beside the other planogram routes:

```elixir
live "/planogram/:id", Planogram.TaskDetailLive, :show
```

- [ ] **Step 2: Write the failing test**

File: `test/showcase_web/live/planogram/task_detail_live_test.exs`

```elixir
defmodule ShowcaseWeb.Planogram.TaskDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  use Oban.Testing, repo: Showcase.Repo
  import Phoenix.LiveViewTest

  alias Showcase.Planogram
  alias Showcase.Planogram.{Seed, MockPrompts, VerificationTask, Worker}
  alias Showcase.Repo

  setup do
    Seed.seed()
    MockPrompts.register_all()
    :ok
  end

  describe "pending task" do
    test "shows the planogram name + Run analysis button", %{conn: conn} do
      task = a_task("compliant")
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Downtown Mart"
      assert html =~ "Run analysis"
      assert html =~ "pending"
    end
  end

  describe "complete task" do
    test "renders compliance gauge, per-row, issues, suggestions, cost badge", %{conn: conn} do
      task = a_task("compliant") |> run_to_completion()

      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "96%"                          # gauge
      assert html =~ "Top shelf"                    # per-row
      assert html =~ "Shelf matches planogram"      # exec summary
      assert html =~ "no action needed"             # suggestion
      assert html =~ "tok"                          # CostBadge
      assert html =~ "Raw JSON"                     # JSONInspector
    end

    test "major_issues result renders high-severity issue rows", %{conn: conn} do
      task = a_task("major_issues") |> run_to_completion()
      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "Sprite 500ml MISSING"
      assert html =~ "high"
    end
  end

  describe "partial result (force truncation)" do
    test "renders a 'partial salvage' banner when result.partial? is true", %{conn: conn} do
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "compliant",
        text: ~s|{"compliance_score": 75, "rows": [{"name":"Top|,
        stop_reason: "max_tokens",
        input_tokens: 100,
        output_tokens: 50
      )

      task = a_task("compliant")
      {:ok, _} = Planogram.enqueue_analysis(task.id, max_tokens: 200)
      [job] = all_enqueued()
      Oban.Testing.perform_job(Worker, job.args)

      {:ok, _view, html} = live(conn, "/planogram/#{task.id}")
      assert html =~ "response was truncated"  # partial banner copy
      assert html =~ "75%"
    end
  end

  defp a_task(scenario) do
    Repo.get_by!(VerificationTask, scenario: scenario)
  end

  defp run_to_completion(task) do
    {:ok, _} = Planogram.enqueue_analysis(task.id)
    [job] = all_enqueued()
    Oban.Testing.perform_job(Worker, job.args)
    Repo.get!(VerificationTask, task.id)
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/showcase_web/live/planogram/task_detail_live_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 4: Write the ComplianceGauge component**

File: `lib/showcase_web/live/planogram/components/compliance_gauge.ex`

```elixir
defmodule ShowcaseWeb.Planogram.Components.ComplianceGauge do
  use Phoenix.Component

  attr :pct, :integer, required: true
  attr :size, :integer, default: 140

  def compliance_gauge(assigns) do
    radius = div(assigns.size, 2) - 8
    circumference = 2 * :math.pi() * radius
    dash = circumference * (1 - assigns.pct / 100)

    color =
      cond do
        assigns.pct >= 90 -> "stroke-emerald-500"
        assigns.pct >= 60 -> "stroke-amber-500"
        true -> "stroke-rose-500"
      end

    assigns =
      assigns
      |> assign(:radius, radius)
      |> assign(:circumference, circumference)
      |> assign(:dash, dash)
      |> assign(:color, color)
      |> assign(:cx, div(assigns.size, 2))
      |> assign(:cy, div(assigns.size, 2))

    ~H"""
    <div class="relative inline-block" style={"width: #{@size}px; height: #{@size}px"}>
      <svg width={@size} height={@size} viewBox={"0 0 #{@size} #{@size}"}>
        <circle cx={@cx} cy={@cy} r={@radius} class="stroke-zinc-200" stroke-width="10" fill="none"/>
        <circle cx={@cx} cy={@cy} r={@radius}
                class={["transition-all", @color]} stroke-width="10" fill="none"
                stroke-linecap="round"
                stroke-dasharray={"#{Float.round(@circumference, 2)}"}
                stroke-dashoffset={"#{Float.round(@dash, 2)}"}
                transform={"rotate(-90 #{@cx} #{@cy})"}/>
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-3xl font-semibold"><%= @pct %>%</span>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Write the PerRowTable component**

File: `lib/showcase_web/live/planogram/components/per_row_table.ex`

```elixir
defmodule ShowcaseWeb.Planogram.Components.PerRowTable do
  use Phoenix.Component

  attr :rows, :list, required: true

  def per_row_table(assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead class="text-xs uppercase tracking-wide text-zinc-500">
        <tr>
          <th class="text-left py-2">Row</th>
          <th class="text-left py-2">Status</th>
          <th class="text-left py-2">Found products</th>
          <th class="text-left py-2">Issues</th>
        </tr>
      </thead>
      <tbody class="divide-y">
        <tr :for={row <- @rows}>
          <td class="py-2 font-medium"><%= row.name %></td>
          <td class="py-2">
            <span class={["rounded px-2 py-0.5 text-xs",
                          "bg-#{row.status_color}-100 text-#{row.status_color}-700"]}>
              <%= row.status %>
            </span>
          </td>
          <td class="py-2">
            <%= for p <- row.found_products do %>
              <div><%= p["name"] %> <span class="text-zinc-400">×<%= p["qty"] %></span></div>
            <% end %>
          </td>
          <td class="py-2 text-zinc-700">
            <ul class="list-disc list-inside">
              <li :for={iss <- row.issues}><%= iss %></li>
            </ul>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end
end
```

- [ ] **Step 6: Write TaskDetailLive**

File: `lib/showcase_web/live/planogram/task_detail_live.ex`

```elixir
defmodule ShowcaseWeb.Planogram.TaskDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.Impl.ResultRenderer
  alias Showcase.Common.AnthropicClient.Types.Usage

  alias ShowcaseWeb.Components.{CostBadge, JSONInspector}
  alias ShowcaseWeb.Planogram.Components.{ComplianceGauge, PerRowTable}

  import CostBadge, only: [cost_badge: 1]
  import JSONInspector, only: [json_inspector: 1]
  import ComplianceGauge
  import PerRowTable

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Planogram.get_task!(String.to_integer(id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Showcase.PubSub, Showcase.Planogram.VisionPipeline.topic(task.id))
    end

    {:ok, assign_task(socket, task)}
  end

  defp assign_task(socket, task) do
    rendered = if task.result, do: ResultRenderer.render(task.result), else: nil
    usage = if task.usage, do: usage_struct(task.usage), else: nil

    socket
    |> assign(:task, task)
    |> assign(:rendered, rendered)
    |> assign(:usage, usage)
  end

  defp usage_struct(%{"input_tokens" => i, "output_tokens" => o, "cost_estimate_cents" => c}) do
    %Usage{input_tokens: i, output_tokens: o, cost_estimate_cents: c}
  end

  @impl true
  def handle_event("run_analysis", _, socket) do
    Planogram.enqueue_analysis(socket.assigns.task.id)
    {:noreply, put_flash(socket, :info, "Analysis enqueued.")}
  end

  @impl true
  def handle_info({:planogram, _, _task_id}, socket) do
    {:noreply, assign_task(socket, Planogram.get_task!(socket.assigns.task.id))}
  end

  def handle_info({:planogram, :task_failed, _task_id, _reason}, socket) do
    {:noreply, assign_task(socket, Planogram.get_task!(socket.assigns.task.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-xl font-semibold"><%= @task.store_name %></h1>
            <p class="text-sm text-zinc-500 mt-1">
              <%= @task.planogram.name %> · due <%= @task.due_date %> ·
              <span class={["rounded px-2 py-0.5 text-xs", status_classes(@task.status)]}>
                <%= @task.status %>
              </span>
            </p>
          </div>
          <a href="/planogram" class="text-sm text-zinc-500 underline">&larr; Back</a>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-6 py-6 space-y-6">
        <%= case @task.status do %>
          <% s when s in ["pending"] -> %>
            <.empty_state />
            <button phx-click="run_analysis"
                    class="rounded bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700">
              Run analysis
            </button>

          <% "analyzing" -> %>
            <div class="rounded border bg-blue-50 px-4 py-3 text-sm text-blue-800">
              Calling Claude vision API…
            </div>

          <% "failed" -> %>
            <div class="rounded border bg-rose-50 px-4 py-3 text-sm text-rose-800">
              Analysis failed: <%= @task.error_reason %>
            </div>

          <% "complete" -> %>
            <.result_panel rendered={@rendered} usage={@usage} raw={@task.result} />
        <% end %>
      </main>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="rounded border bg-white p-6 text-center text-sm text-zinc-500">
      No result yet. Capture a photo (or use the bundled scenario) and run analysis.
    </div>
    """
  end

  attr :rendered, :map, required: true
  attr :usage, :any, required: true
  attr :raw, :map, required: true

  defp result_panel(assigns) do
    ~H"""
    <div :if={@rendered.partial?} class="rounded border border-amber-300 bg-amber-50 px-4 py-2 text-xs text-amber-800">
      The AI response was truncated. Showing salvaged fields via ResilientJSONParser.
    </div>

    <section class="rounded border bg-white p-5">
      <div class="flex items-center gap-6">
        <.compliance_gauge pct={@rendered.gauge_pct} />
        <div class="flex-1">
          <h2 class="text-lg font-medium">Executive summary</h2>
          <p class="text-sm text-zinc-700 mt-1"><%= @rendered.executive_summary %></p>
          <div class="mt-3 flex items-center gap-3">
            <.cost_badge :if={@usage} usage={@usage} />
            <span class="text-xs text-zinc-400">photo quality: <%= @rendered.photo_quality.score || "?" %></span>
          </div>
        </div>
      </div>
    </section>

    <section :if={@rendered.rows != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Per-row breakdown</h2>
      <.per_row_table rows={@rendered.rows} />
    </section>

    <section :if={@rendered.issues != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Issues (<%= length(@rendered.issues) %>)</h2>
      <ul class="space-y-3">
        <li :for={iss <- @rendered.issues} class="flex gap-3 items-start">
          <span class={["rounded px-2 py-0.5 text-xs uppercase tracking-wide",
                        "bg-#{iss.severity_color}-100 text-#{iss.severity_color}-700"]}>
            <%= iss.severity %>
          </span>
          <div class="flex-1">
            <div class="font-medium"><%= iss.type %></div>
            <div class="text-sm text-zinc-700"><%= iss.description %></div>
            <div class="text-xs text-zinc-500 mt-1">Impact: <%= iss.business_impact %></div>
          </div>
        </li>
      </ul>
    </section>

    <section :if={@rendered.suggestions != []} class="rounded border bg-white p-5">
      <h2 class="text-lg font-medium mb-3">Suggested actions</h2>
      <ul class="list-disc list-inside text-sm text-zinc-700 space-y-1">
        <li :for={s <- @rendered.suggestions}><%= s %></li>
      </ul>
    </section>

    <.json_inspector data={@raw} />
    """
  end

  defp status_classes("pending"), do: "bg-zinc-100 text-zinc-700"
  defp status_classes("analyzing"), do: "bg-blue-100 text-blue-700"
  defp status_classes("complete"), do: "bg-emerald-100 text-emerald-700"
  defp status_classes("failed"), do: "bg-rose-100 text-rose-700"
  defp status_classes(_), do: "bg-zinc-100"
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/showcase_web/live/planogram/task_detail_live_test.exs`
Expected: PASS — all assertions green.

- [ ] **Step 8: Commit**

```bash
git add lib/showcase_web/live/planogram/task_detail_live.ex \
        lib/showcase_web/live/planogram/components/ \
        lib/showcase_web/router.ex \
        test/showcase_web/live/planogram/task_detail_live_test.exs
git commit -m "feat(planogram): TaskDetailLive with gauge + per-row + issues + cost badge + JSON inspector"
```

---

### Task 13: MobileCaptureLive (TDD)

**Files:**
- Create: `lib/showcase_web/live/planogram/mobile_capture_live.ex`
- Test: `test/showcase_web/live/planogram/mobile_capture_live_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase_web/live/planogram/mobile_capture_live_test.exs`

```elixir
defmodule ShowcaseWeb.Planogram.MobileCaptureLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Showcase.Planogram.{Seed, VerificationTask}
  alias Showcase.Repo

  setup do
    Seed.seed()
    :ok
  end

  describe "GET /planogram/mobile/:token" do
    test "renders the capture UI when token is valid", %{conn: conn} do
      task = first_pending_task()
      {:ok, _view, html} = live(conn, "/planogram/mobile/#{task.mobile_token}")
      assert html =~ task.store_name
      assert html =~ "Capture photo"
    end

    test "renders an error when token is unknown", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/planogram/mobile/not-a-real-token")
      assert html =~ "Link is no longer valid"
    end

    test "renders 'already processed' when task is complete", %{conn: conn} do
      task = first_pending_task()
      task
      |> VerificationTask.changeset(%{status: "complete"})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, "/planogram/mobile/#{task.mobile_token}")
      assert html =~ "already been processed"
    end
  end

  defp first_pending_task do
    Repo.get_by!(VerificationTask, scenario: "compliant")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase_web/live/planogram/mobile_capture_live_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Write the LiveView**

File: `lib/showcase_web/live/planogram/mobile_capture_live.ex`

```elixir
defmodule ShowcaseWeb.Planogram.MobileCaptureLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Planogram
  alias Showcase.Planogram.MobileHandoff

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case MobileHandoff.find_task_by_token(token) do
      {:ok, task} ->
        socket =
          socket
          |> assign(:task, task)
          |> assign(:error, nil)
          |> allow_upload(:photo,
            accept: ~w(.png .jpg .jpeg),
            max_entries: 1,
            max_file_size: 8_000_000
          )

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, assign(socket, task: nil, error: :not_found)}

      {:error, :already_processed} ->
        {:ok, assign(socket, task: nil, error: :already_processed)}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("submit", _params, socket) do
    [entry | _] = socket.assigns.uploads.photo.entries

    consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, _entry ->
      bytes = File.read!(tmp_path)
      {:ok, updated} = MobileHandoff.finalize_upload(socket.assigns.task, bytes)
      Planogram.enqueue_analysis(updated.id)
      {:ok, updated}
    end)

    {:noreply,
     socket
     |> assign(:task, Planogram.get_task!(socket.assigns.task.id))
     |> put_flash(:info, "Photo uploaded — analysis enqueued. You can close this tab.")}
  end

  @impl true
  def render(%{error: :not_found} = assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-6 bg-zinc-50">
      <div class="rounded border bg-white p-6 max-w-md text-center">
        <h1 class="text-lg font-semibold mb-2">Link is no longer valid</h1>
        <p class="text-sm text-zinc-600">
          The mobile-capture link could not be matched to a verification task.
        </p>
      </div>
    </div>
    """
  end

  def render(%{error: :already_processed} = assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-6 bg-zinc-50">
      <div class="rounded border bg-white p-6 max-w-md text-center">
        <h1 class="text-lg font-semibold mb-2">Already done</h1>
        <p class="text-sm text-zinc-600">
          This audit has already been processed. Switch back to the desktop view.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-4 bg-zinc-50">
      <header class="mb-4">
        <h1 class="text-xl font-semibold"><%= @task.store_name %></h1>
        <p class="text-sm text-zinc-500"><%= @task.planogram.name %></p>
      </header>

      <form phx-submit="submit" phx-change="validate" class="space-y-4">
        <label class="block">
          <span class="block text-sm font-medium mb-2">Capture photo</span>
          <.live_file_input upload={@uploads.photo} class="w-full" />
        </label>

        <div :for={entry <- @uploads.photo.entries} class="text-sm text-zinc-600">
          <%= entry.client_name %> — <%= entry.progress %>%
          <div :for={err <- upload_errors(@uploads.photo, entry)} class="text-rose-600 text-xs">
            <%= error_to_string(err) %>
          </div>
        </div>

        <button type="submit"
                disabled={@uploads.photo.entries == []}
                class="w-full rounded bg-emerald-600 px-4 py-3 text-base font-medium text-white hover:bg-emerald-700 disabled:opacity-40">
          Upload and analyze
        </button>
      </form>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "Photo is too large (max 8 MB)."
  defp error_to_string(:not_accepted), do: "Not a supported file type (.png, .jpg)."
  defp error_to_string(_), do: "Upload error."
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase_web/live/planogram/mobile_capture_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/showcase_web/live/planogram/mobile_capture_live.ex \
        test/showcase_web/live/planogram/mobile_capture_live_test.exs
git commit -m "feat(planogram): MobileCaptureLive at /planogram/mobile/:token (photo upload + auto-enqueue)"
```

---

### Task 14: TileConfig flip + Dashboard wiring + reset integration

**Files:**
- Modify: `lib/showcase/dashboard/tile_config.ex`
- Test: extend smoke test below

- [ ] **Step 1: Flip the planogram tile to `:live`**

In `lib/showcase/dashboard/tile_config.ex`, replace the planogram entry:

```elixir
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
```

- [ ] **Step 2: Run the dashboard smoke test**

Run: `mix test test/showcase_web/live/dashboard_live_test.exs`
Expected: PASS — the dashboard renders the Planogram tile as live (`<a href="/planogram">`).

- [ ] **Step 3: Run the full seed against dev DB**

```bash
mix ecto.reset
mix run -e "Showcase.Dashboard.live_seeders() |> Enum.each(& &1.seed())"
```

Expected: all 4 live demos seed without error. The Reset admin page (`/admin/reset`) should now enumerate Planogram alongside the others.

- [ ] **Step 4: Manually verify reset wipes uploads**

(Document only — no automated test.) In `lib/showcase/common/reset.ex`, the `truncate_tables` step handles DB. Photo uploads under `priv/static/uploads/planogram/` are NOT yet wiped by reset — add a hook.

Modify the Seed module to also clear the upload dir:

In `lib/showcase/planogram/seed.ex`, add to `seed/0` before the `Repo.transaction`:

```elixir
def seed do
  clear_uploads()

  Repo.transaction(fn ->
    planogram = upsert_planogram()
    upsert_tasks(planogram)
  end)

  :ok
end

defp clear_uploads do
  upload_dir = "priv/static/uploads/planogram"
  File.rm_rf!(upload_dir)
  File.mkdir_p!(upload_dir)
end
```

- [ ] **Step 5: Commit**

```bash
git add lib/showcase/dashboard/tile_config.ex lib/showcase/planogram/seed.ex
git commit -m "feat(planogram): flip tile to :live + clear uploads on reset"
```

---

### Task 15: Final smoke test + phase-5 tag

**Files:**
- Run full suite
- Tag commit

- [ ] **Step 1: Run the whole test suite**

Run: `mix test`
Expected: All tests green. Should be ~250 tests + 1 property (or close — Phase 5 adds roughly 30 new tests).

- [ ] **Step 2: Start the dev server and walk through the demo manually**

Run: `mix phx.server`
In a browser:
- `http://localhost:4321/` — Dashboard. Planogram tile renders as "Live".
- Click into Planogram. See 3 tasks bucketed (Overdue / Today / Tomorrow).
- Click "Run analysis" on Downtown Mart → status flips analyzing → complete. Navigate to detail.
- Detail view: 96% gauge, exec summary, per-row, JSON inspector visible.
- Back to merchandiser. Click "Open on phone" on Downtown Mart → QR renders. Scan with phone (or open the URL printed under the QR in another browser tab).
- Upload a photo from the phone → see desktop's status update on PubSub.
- Switch to Manager role. Create a new task with today's date. Verify it appears.
- Switch to Admin. Verify model/scenario summary.
- Click "Force truncation" on a fresh task → status complete → detail page shows the partial-salvage banner.
- Hit `/admin/reset` → reset all → reload `/planogram` → 3 baseline tasks restored.

- [ ] **Step 3: Tag the phase**

Run:
```bash
git tag phase-5
```

- [ ] **Step 4: Push branches & tags (or merge — depending on the user's chosen flow)**

(Stop here — `finishing-a-development-branch` will be invoked next to handle the merge / PR / keep choice.)

---

## Self-review checklist

- [x] **Spec coverage** — every line item from §4.3 (role switcher, upload planogram, create task with past dates, capture photo, run analysis, force truncation, single rich JSON call, per-row breakdown, issues, photo quality, extracted products, QR handoff, date-driven overdue) is in a task.
- [x] **Placeholder scan** — no `TBD`, no "handle edge cases", no "similar to Task N". Code blocks complete.
- [x] **Type consistency** — `VerificationTask` always lower-snake `status` strings (`"pending"` / `"analyzing"` / `"complete"` / `"failed"`); `MockPrompts.register_all/0` referenced by name in tests; `VisionPipeline.topic/1` used by both LiveViews; `MobileHandoff.generate_token/0` referenced in Seed.
- [x] **Minimum-states preference** — 4 statuses (one less than spec's 5 if you'd called "captured" a state). Roles are a UI-only enum, not a DB state machine.
- [x] **No cross-demo joins** — Planogram tables (`pg_*`) never reference `of_*` / `rf_*` / `ia_*`.
- [x] **AnthropicClient through behaviour** — never imports Anthropix directly.
- [x] **`impl/` pure** — Overdue, VisionRequest, ResultRenderer have zero side effects.
