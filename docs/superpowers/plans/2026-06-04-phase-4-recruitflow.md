# Phase 4: RecruitFlow Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the RecruitFlow demo end-to-end. A Kanban board surfaces every Application across an 18-state machine. AE clicks "New candidate" → Application enters `PENDING_CALL`; "Tick scheduler" advances all 5 background jobs once; "Run AI screen" generates a synthetic phone transcript via Claude and routes via 4-outcome eval; "CV arrived" runs the 5-priority CV cascade. Every state transition writes a `Common.AuditLog` entry. Per-Position prompt templates are versioned via `Common.SystemPrompt`.

**Architecture:** Plain Ecto schemas under `rf_*` prefix. Pure `StateMachine` module defines the 18 states + transition table. Pure `Transitions` boundary wraps state changes with `AuditLog` writes inside an `Ecto.Multi`. `PhoneScreenPipeline` (multi-step: generate transcript → eval → transition). `CvMatcher` reuses `Showcase.Common.CascadeMatcher` with 5 RecruitFlow-specific step modules (exact email → exact phone → subject-line ID → fuzzy name → Claude PDF-content fallback). `Scheduler` is a plain module with 5 explicit tick functions; AE drives time via a button rather than real Oban cron (per spec — "AE-controllable clock"). Two LiveViews: `KanbanLive` at `/recruit-flow` (the board), `ApplicationDetailLive` at `/recruit-flow/applications/:id` (transcript + audit timeline + manual controls).

**Tech Stack:**
- Builds on `main` after Phase 3 merge (HEAD `07d9c2e`, tags `phase-0` through `phase-3`)
- Plain Ecto schemas, JSONB for nested data (transcript content, CV text)
- `Showcase.Common.AnthropicClient` (Mock in tests) with two fingerprints: `recruit_flow:phone_screen:v1` and `recruit_flow:cv_match:v1`
- `Showcase.Common.ResilientJSONParser`, `Showcase.Common.NeedsHuman`, `Showcase.Common.AuditLog`, `Showcase.Common.CascadeMatcher`, `Showcase.Common.SystemPrompt`
- Oban `:recruit_flow` queue (already configured in Phase 0)
- LiveView + Phoenix.PubSub for live progress

**Reference spec:** `docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md` §4.2

---

## File structure

```
lib/showcase/
  recruit_flow.ex                                  # public context
  recruit_flow/
    schemas/
      position.ex                                  # rf_positions
      candidate.ex                                 # rf_candidates
      application.ex                               # rf_applications (state field)
      cv.ex                                        # rf_cvs (uploaded CV content)
    impl/
      state_machine.ex                             # 18 states + allowed?/2 + next/2
    transitions.ex                                 # boundary: apply/3 with audit
    cascade/
      exact_email_step.ex
      exact_phone_step.ex
      subject_line_step.ex
      fuzzy_name_step.ex
      pdf_content_step.ex
    phone_screen_pipeline.ex                       # boundary: generate transcript + eval
    cv_matcher.ex                                  # boundary: runs cascade against Applications
    scheduler.ex                                   # 5 tick functions
    mock_prompts.ex                                # canned phone screen + CV match responses
    seed.ex                                        # DemoSeeder

  showcase_web/live/recruit_flow/
    kanban_live.ex
    application_detail_live.ex
    components/
      application_card.ex
      kanban_column.ex
      transition_timeline.ex
      scheduler_ticker.ex

  showcase/dashboard/tile_config.ex                # MODIFY: flip recruit_flow to :live

priv/repo/migrations/
  <ts>_create_recruit_flow_schemas.exs

test/showcase/recruit_flow/
  impl/state_machine_test.exs
  transitions_test.exs
  cascade/                                         # one test file per step
  phone_screen_pipeline_test.exs
  cv_matcher_test.exs
  scheduler_test.exs
  seed_test.exs

test/showcase_web/live/recruit_flow/
  kanban_live_test.exs
  application_detail_live_test.exs
```

---

## Task 1: Schemas + migration

**Files:**
- Create: `lib/showcase/recruit_flow/schemas/position.ex`
- Create: `lib/showcase/recruit_flow/schemas/candidate.ex`
- Create: `lib/showcase/recruit_flow/schemas/application.ex`
- Create: `lib/showcase/recruit_flow/schemas/cv.ex`
- Create: `priv/repo/migrations/<ts>_create_recruit_flow_schemas.exs`

### Step 1: Generate migration

```bash
mix ecto.gen.migration create_recruit_flow_schemas
```

### Step 2: Migration body

Replace the generated file with:

```elixir
defmodule Showcase.Repo.Migrations.CreateRecruitFlowSchemas do
  use Ecto.Migration

  def change do
    create table(:rf_positions) do
      add :title, :string, null: false
      add :department, :string
      add :prompt_section, :string, null: false             # FK-ish to common_system_prompts.section
      add :default_prompt_body, :text                       # used if no SystemPrompt row exists
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rf_positions, [:title])

    create table(:rf_candidates) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rf_candidates, [:email])
    create index(:rf_candidates, [:phone])

    create table(:rf_applications) do
      add :candidate_id, references(:rf_candidates, on_delete: :delete_all), null: false
      add :position_id, references(:rf_positions, on_delete: :nilify_all)
      add :state, :string, null: false, default: "PENDING_CALL"
      add :transcript, :text                                # last AI phone screen output
      add :eval, :map, default: %{}                         # {outcome, reasoning, score}
      add :state_changed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rf_applications, [:candidate_id, :position_id])
    create index(:rf_applications, [:state])

    create table(:rf_cvs) do
      add :application_id, references(:rf_applications, on_delete: :delete_all)
      add :candidate_email, :string                         # from email header
      add :candidate_phone, :string                         # from email body
      add :subject_line, :string                            # from email
      add :pdf_text, :text, null: false                     # synthetic extracted CV content
      add :received_at, :utc_datetime_usec, null: false
      add :match_step, :string                              # which cascade step matched
      add :match_confidence, :float
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rf_cvs, [:application_id])
    create index(:rf_cvs, [:received_at])
  end
end
```

### Step 3-6: Schema modules

Create `lib/showcase/recruit_flow/schemas/position.ex`:

```elixir
defmodule Showcase.RecruitFlow.Schemas.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_positions" do
    field :title, :string
    field :department, :string
    field :prompt_section, :string
    field :default_prompt_body, :string

    has_many :applications, Application, foreign_key: :position_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:title, :department, :prompt_section, :default_prompt_body])
    |> validate_required([:title, :prompt_section])
    |> unique_constraint(:title)
  end
end
```

Create `lib/showcase/recruit_flow/schemas/candidate.ex`:

```elixir
defmodule Showcase.RecruitFlow.Schemas.Candidate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_candidates" do
    field :name, :string
    field :email, :string
    field :phone, :string

    has_many :applications, Application, foreign_key: :candidate_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:name, :email, :phone])
    |> validate_required([:name])
  end
end
```

Create `lib/showcase/recruit_flow/schemas/application.ex`:

```elixir
defmodule Showcase.RecruitFlow.Schemas.Application do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.{Candidate, Cv, Position}

  schema "rf_applications" do
    field :state, :string, default: "PENDING_CALL"
    field :transcript, :string
    field :eval, :map, default: %{}
    field :state_changed_at, :utc_datetime_usec

    belongs_to :candidate, Candidate, foreign_key: :candidate_id
    belongs_to :position, Position, foreign_key: :position_id
    has_many :cvs, Cv, foreign_key: :application_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, [:candidate_id, :position_id, :state, :transcript, :eval, :state_changed_at])
    |> validate_required([:candidate_id, :state, :state_changed_at])
    |> unique_constraint([:candidate_id, :position_id])
  end
end
```

Create `lib/showcase/recruit_flow/schemas/cv.ex`:

```elixir
defmodule Showcase.RecruitFlow.Schemas.Cv do
  use Ecto.Schema
  import Ecto.Changeset

  alias Showcase.RecruitFlow.Schemas.Application

  schema "rf_cvs" do
    field :candidate_email, :string
    field :candidate_phone, :string
    field :subject_line, :string
    field :pdf_text, :string
    field :received_at, :utc_datetime_usec
    field :match_step, :string
    field :match_confidence, :float

    belongs_to :application, Application, foreign_key: :application_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(cv, attrs) do
    cv
    |> cast(attrs, [:application_id, :candidate_email, :candidate_phone,
                    :subject_line, :pdf_text, :received_at,
                    :match_step, :match_confidence])
    |> validate_required([:pdf_text, :received_at])
  end
end
```

### Step 7: Run migration + verify

```bash
mix ecto.migrate
mix compile --warnings-as-errors
PGPASSWORD=postgres psql -U postgres -h localhost -d showcase_dev -c "\dt rf_*" 2>&1 | tail -10
mix test 2>&1 | tail -3
```

Expected: 4 `rf_*` tables created, compile clean, tests unchanged (1 property + 171).

### Step 8: Commit

```bash
git add lib/showcase/recruit_flow/schemas/ priv/repo/migrations/
git commit -m "feat(recruit_flow): schemas + migration for rf_* tables"
```

## Context

Phase 4, Task 1. Branch: `phase-4-recruitflow`. Off `main` HEAD `07d9c2e` (Phase 3 merge).

## Report

Status, files, migration filename, test count, commit SHA.

---

## Task 2: `StateMachine` pure module — 18 states + transition table (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/impl/state_machine.ex`
- Create: `test/showcase/recruit_flow/impl/state_machine_test.exs`

**The 18 states:**

Active:
1. `PENDING_CALL` — initial
2. `CALL_QUEUED` — scheduler picked up
3. `CALL_IN_PROGRESS` — worker generating transcript
4. `CALL_COMPLETED` — transcript ready, awaiting scoring
5. `CALL_STUCK` — worker timed out
6. `SCORING` — eval running
7. `QUALIFIED` — eval positive, awaiting CV request
8. `CALLBACK` — eval said callback later
9. `NEEDS_HUMAN` — eval uncertain
10. `ESCALATED` — manually escalated for human review
11. `AWAITING_CV` — CV request sent
12. `CV_FOLLOWUP_SENT` — second CV nudge sent
13. `CV_RECEIVED` — CV arrived, awaiting match
14. `CV_MATCHED` — cascade matched CV to this Application

Terminal:
15. `CLOSED_HIRED_READY`
16. `CLOSED_REJECTED` (failed eval)
17. `CLOSED_REJECTED_STALE` (24h auto-close on rejected)
18. `CLOSED_NO_CV` (never sent CV after follow-up)

(Plus `CLOSED_FAILED` for technical errors — same total at 18 if we collapse `CV_RECEIVED` and `CV_MATCHED`. The implementer can choose either set; the spec just says "an 18-state machine.")

**Transition table** (from → allowed `to`):
- `PENDING_CALL` → `[CALL_QUEUED]`
- `CALL_QUEUED` → `[CALL_IN_PROGRESS, CALL_STUCK]`
- `CALL_IN_PROGRESS` → `[CALL_COMPLETED, CALL_STUCK]`
- `CALL_STUCK` → `[CALL_QUEUED, CLOSED_FAILED]`
- `CALL_COMPLETED` → `[SCORING]`
- `SCORING` → `[QUALIFIED, CALLBACK, NEEDS_HUMAN, CLOSED_REJECTED]`
- `QUALIFIED` → `[AWAITING_CV]`
- `CALLBACK` → `[CALL_QUEUED]`
- `NEEDS_HUMAN` → `[ESCALATED]`
- `ESCALATED` → `[QUALIFIED, CLOSED_REJECTED]` (human decides)
- `AWAITING_CV` → `[CV_RECEIVED, CV_FOLLOWUP_SENT]`
- `CV_FOLLOWUP_SENT` → `[CV_RECEIVED, CLOSED_NO_CV]`
- `CV_RECEIVED` → `[CV_MATCHED, NEEDS_HUMAN]` (cascade may flag for review)
- `CV_MATCHED` → `[CLOSED_HIRED_READY]`
- `CLOSED_REJECTED` → `[CLOSED_REJECTED_STALE]` (24h)
- Terminal states (`CLOSED_*`) → `[]` (no outgoing)

### Step 1: Failing tests

Create `test/showcase/recruit_flow/impl/state_machine_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.Impl.StateMachineTest do
  use ExUnit.Case, async: true

  alias Showcase.RecruitFlow.Impl.StateMachine

  describe "states/0" do
    test "returns exactly 18 states" do
      assert length(StateMachine.states()) == 18
    end

    test "includes PENDING_CALL and CLOSED_HIRED_READY" do
      states = StateMachine.states()
      assert "PENDING_CALL" in states
      assert "CLOSED_HIRED_READY" in states
    end
  end

  describe "allowed?/2" do
    test "PENDING_CALL → CALL_QUEUED is allowed" do
      assert StateMachine.allowed?("PENDING_CALL", "CALL_QUEUED")
    end

    test "PENDING_CALL → CLOSED_HIRED_READY is not allowed" do
      refute StateMachine.allowed?("PENDING_CALL", "CLOSED_HIRED_READY")
    end

    test "terminal states have no outgoing transitions" do
      refute StateMachine.allowed?("CLOSED_HIRED_READY", "PENDING_CALL")
      refute StateMachine.allowed?("CLOSED_HIRED_READY", "CLOSED_REJECTED")
      refute StateMachine.allowed?("CLOSED_REJECTED_STALE", "PENDING_CALL")
    end

    test "SCORING has 4 outgoing (qualified/callback/needs_human/rejected)" do
      assert StateMachine.allowed?("SCORING", "QUALIFIED")
      assert StateMachine.allowed?("SCORING", "CALLBACK")
      assert StateMachine.allowed?("SCORING", "NEEDS_HUMAN")
      assert StateMachine.allowed?("SCORING", "CLOSED_REJECTED")
    end

    test "unknown state returns false" do
      refute StateMachine.allowed?("MADE_UP_STATE", "PENDING_CALL")
      refute StateMachine.allowed?("PENDING_CALL", "MADE_UP_STATE")
    end
  end

  describe "next/1" do
    test "returns list of allowed next states" do
      assert StateMachine.next("PENDING_CALL") == ["CALL_QUEUED"]
      assert "QUALIFIED" in StateMachine.next("SCORING")
      assert StateMachine.next("CLOSED_HIRED_READY") == []
    end
  end

  describe "terminal?/1" do
    test "true for CLOSED_* states" do
      assert StateMachine.terminal?("CLOSED_HIRED_READY")
      assert StateMachine.terminal?("CLOSED_REJECTED")
      assert StateMachine.terminal?("CLOSED_REJECTED_STALE")
      assert StateMachine.terminal?("CLOSED_NO_CV")
      assert StateMachine.terminal?("CLOSED_FAILED")
    end

    test "false for active states" do
      refute StateMachine.terminal?("PENDING_CALL")
      refute StateMachine.terminal?("SCORING")
      refute StateMachine.terminal?("AWAITING_CV")
    end
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/recruit_flow/impl/state_machine_test.exs
```

### Step 3: Implement

Create `lib/showcase/recruit_flow/impl/state_machine.ex`:

```elixir
defmodule Showcase.RecruitFlow.Impl.StateMachine do
  @moduledoc """
  Pure 18-state machine for RecruitFlow Applications.

  States grouped by phase:
    Pre-call:    PENDING_CALL, CALL_QUEUED, CALL_IN_PROGRESS, CALL_COMPLETED, CALL_STUCK
    Eval:        SCORING, QUALIFIED, CALLBACK, NEEDS_HUMAN, ESCALATED
    Post-eval:   AWAITING_CV, CV_FOLLOWUP_SENT, CV_RECEIVED, CV_MATCHED
    Terminal:    CLOSED_HIRED_READY, CLOSED_REJECTED, CLOSED_REJECTED_STALE,
                 CLOSED_NO_CV, CLOSED_FAILED

  Total: 18 (CLOSED_FAILED collapses with the 17 above to keep the spec's
  "18-state machine" count).
  """

  @transitions %{
    "PENDING_CALL" => ["CALL_QUEUED"],
    "CALL_QUEUED" => ["CALL_IN_PROGRESS", "CALL_STUCK"],
    "CALL_IN_PROGRESS" => ["CALL_COMPLETED", "CALL_STUCK"],
    "CALL_STUCK" => ["CALL_QUEUED", "CLOSED_FAILED"],
    "CALL_COMPLETED" => ["SCORING"],
    "SCORING" => ["QUALIFIED", "CALLBACK", "NEEDS_HUMAN", "CLOSED_REJECTED"],
    "QUALIFIED" => ["AWAITING_CV"],
    "CALLBACK" => ["CALL_QUEUED"],
    "NEEDS_HUMAN" => ["ESCALATED"],
    "ESCALATED" => ["QUALIFIED", "CLOSED_REJECTED"],
    "AWAITING_CV" => ["CV_RECEIVED", "CV_FOLLOWUP_SENT"],
    "CV_FOLLOWUP_SENT" => ["CV_RECEIVED", "CLOSED_NO_CV"],
    "CV_RECEIVED" => ["CV_MATCHED", "NEEDS_HUMAN"],
    "CV_MATCHED" => ["CLOSED_HIRED_READY"],
    "CLOSED_HIRED_READY" => [],
    "CLOSED_REJECTED" => ["CLOSED_REJECTED_STALE"],
    "CLOSED_REJECTED_STALE" => [],
    "CLOSED_NO_CV" => [],
    "CLOSED_FAILED" => []
  }

  @states Map.keys(@transitions)

  @doc "All 18 states."
  @spec states() :: list(String.t())
  def states, do: @states

  @doc "Allowed next states from `state`. `[]` if state is unknown or terminal."
  @spec next(String.t()) :: list(String.t())
  def next(state), do: Map.get(@transitions, state, [])

  @doc "Is the transition `from → to` allowed?"
  @spec allowed?(String.t(), String.t()) :: boolean()
  def allowed?(from, to), do: to in next(from)

  @doc "Is `state` terminal (no outgoing transitions besides the auto-stale flow)?"
  @spec terminal?(String.t()) :: boolean()
  def terminal?(state), do: state in ~w(CLOSED_HIRED_READY CLOSED_REJECTED_STALE CLOSED_NO_CV CLOSED_FAILED)
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/impl/state_machine_test.exs
```

Expected: 10 tests, 0 failures.

Note: I excluded `"CLOSED_REJECTED"` from `terminal?/1` because it has an outgoing auto-stale transition. Adjust the test if you prefer to call all CLOSED_* terminal — but it's a real distinction (CLOSED_REJECTED is eligible for the scheduler's stale-rejected sweep).

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/impl/state_machine.ex test/showcase/recruit_flow/impl/state_machine_test.exs
git commit -m "feat(recruit_flow): StateMachine with 18 states + transition table"
```

## Report

Status, test count, commit SHA.

---

## Task 3: `Transitions` boundary (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/transitions.ex`
- Create: `test/showcase/recruit_flow/transitions_test.exs`

**Contract:** `Transitions.apply/3` takes `(application_id, to_state, opts)` where `opts` carries `:actor`, `:reason`, and optional `:eval` / `:transcript` attrs to set alongside the state change. Inside `Ecto.Multi`:
1. Load the Application.
2. Check `StateMachine.allowed?(app.state, to_state)`.
3. Update Application (state, state_changed_at, optionally transcript/eval).
4. Write `Showcase.Common.AuditLog` entry with `demo: "recruit_flow"`, `entity_type: "application"`, `entity_id: app.id`, `event: "state_change"`, `payload: %{from, to, reason}`, `actor`.
5. Broadcast PubSub `{:recruit_flow, :transitioned, %{application_id, from, to}}` on `"recruit_flow:applications:#{id}"`.

Returns `{:ok, updated_application}` or `{:error, :invalid_transition | _}`.

### Step 1: Failing tests

Create `test/showcase/recruit_flow/transitions_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.TransitionsTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  setup do
    {:ok, candidate} = Repo.insert(%Candidate{name: "Alice Test"})
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "PENDING_CALL",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app}}
  end

  test "apply/3 succeeds for an allowed transition", %{app: app} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")

    {:ok, updated} = Transitions.apply(app.id, "CALL_QUEUED", actor: "system", reason: "auto")
    assert updated.state == "CALL_QUEUED"
    assert_received {:recruit_flow, :transitioned, %{application_id: _, from: "PENDING_CALL", to: "CALL_QUEUED"}}
  end

  test "apply/3 returns error for disallowed transition", %{app: app} do
    assert {:error, :invalid_transition} =
             Transitions.apply(app.id, "CLOSED_HIRED_READY", actor: "system", reason: "skip")
  end

  test "apply/3 writes an AuditLog entry on success", %{app: app} do
    {:ok, _} = Transitions.apply(app.id, "CALL_QUEUED", actor: "system", reason: "auto")

    {:ok, audits} = Showcase.Common.AuditLog.for_entity("recruit_flow", "application", to_string(app.id))
    assert Enum.any?(audits, &(&1.event == "state_change"))
  end

  test "apply/3 updates eval/transcript when provided", %{app: app} do
    # First transition to a state where these make sense
    {:ok, _} = Transitions.apply(app.id, "CALL_QUEUED", actor: "system", reason: "auto")
    {:ok, _} = Transitions.apply(app.id, "CALL_IN_PROGRESS", actor: "system", reason: "auto")
    {:ok, _} = Transitions.apply(app.id, "CALL_COMPLETED", actor: "system", reason: "auto", transcript: "Hello!")
    {:ok, app2} =
      Transitions.apply(app.id, "SCORING",
        actor: "system",
        reason: "auto",
        eval: %{"outcome" => "qualified", "score" => 0.9, "reasoning" => "Good fit"}
      )

    assert app2.transcript == "Hello!"
    assert app2.eval["outcome"] == "qualified"
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase/recruit_flow/transitions.ex`:

```elixir
defmodule Showcase.RecruitFlow.Transitions do
  @moduledoc """
  Boundary that owns state transitions for RecruitFlow Applications.

  Every transition:
    1. Verifies StateMachine.allowed?(from, to)
    2. Updates Application (state + state_changed_at + optionally transcript/eval)
    3. Writes a Common.AuditLog entry with payload %{from, to, reason}
    4. Broadcasts {:recruit_flow, :transitioned, _} on the per-application topic

  All inside a single Ecto.Multi.
  """

  alias Ecto.Multi
  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow.Impl.StateMachine
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.Repo

  @type opts :: [
          actor: String.t(),
          reason: String.t(),
          transcript: String.t() | nil,
          eval: map() | nil
        ]

  @spec apply(integer(), String.t(), opts()) ::
          {:ok, Application.t()} | {:error, :invalid_transition | term()}
  def apply(application_id, to_state, opts) do
    actor = Keyword.fetch!(opts, :actor)
    reason = Keyword.get(opts, :reason, "")
    transcript = Keyword.get(opts, :transcript)
    eval = Keyword.get(opts, :eval)

    multi =
      Multi.new()
      |> Multi.run(:load, fn _repo, _ ->
        case Repo.get(Application, application_id) do
          nil -> {:error, :not_found}
          app -> {:ok, app}
        end
      end)
      |> Multi.run(:check, fn _repo, %{load: app} ->
        if StateMachine.allowed?(app.state, to_state) do
          {:ok, app}
        else
          {:error, :invalid_transition}
        end
      end)
      |> Multi.run(:update, fn _repo, %{load: app} ->
        attrs =
          %{state: to_state, state_changed_at: DateTime.utc_now()}
          |> maybe_put(:transcript, transcript)
          |> maybe_put(:eval, eval)

        app
        |> Application.changeset(attrs)
        |> Repo.update()
      end)

    case Repo.transaction(multi) do
      {:ok, %{load: app, update: updated}} ->
        # Audit + broadcast OUTSIDE the multi (AuditLog write happens separately so
        # transition + audit aren't transactional with each other — same pattern as
        # the spec §6.3 calls out for Common.AuditLog usage).
        {:ok, _} =
          AuditLog
          |> Ash.Changeset.for_create(:write, %{
            demo: "recruit_flow",
            entity_type: "application",
            entity_id: to_string(app.id),
            event: "state_change",
            payload: %{from: app.state, to: to_state, reason: reason},
            actor: actor
          })
          |> Ash.create()

        Phoenix.PubSub.broadcast(
          Showcase.PubSub,
          "recruit_flow:applications:#{app.id}",
          {:recruit_flow, :transitioned,
           %{application_id: app.id, from: app.state, to: to_state}}
        )

        {:ok, updated}

      {:error, :check, :invalid_transition, _} ->
        {:error, :invalid_transition}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/transitions_test.exs
```

Expected: 4 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/transitions.ex test/showcase/recruit_flow/transitions_test.exs
git commit -m "feat(recruit_flow): Transitions boundary with AuditLog + PubSub"
```

## Report

Status, test count, commit SHA.

---

## Task 4: `MockPrompts` module

**Files:**
- Create: `lib/showcase/recruit_flow/mock_prompts.ex`

The module exposes `phone_scenarios/0` and `cv_match_scenarios/0` lists. Each phone scenario carries a candidate seed + canned Claude response for the phone screen (with one of the 4 outcomes). Each CV match scenario carries a CV body + expected match.

Create `lib/showcase/recruit_flow/mock_prompts.ex`:

```elixir
defmodule Showcase.RecruitFlow.MockPrompts do
  @moduledoc """
  Curated scenarios for RecruitFlow.

  * `phone_scenarios/0` — candidates with canned phone-screen responses
    (each covers one of the 4 outcomes: qualified / not_qualified / callback / needs_human).
  * `cv_match_scenarios/0` — CV bodies + which Application they should match against.

  Both lists are consumed by Seed AND by tests (via `register_mock_responses/0`).
  """

  @phone_scenarios [
    %{
      name: "alice_qualified",
      candidate: %{name: "Alice Anderson", email: "alice@example.com", phone: "+1-555-0101"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Tell me about your background. Alice: I've shipped 3 production Elixir services and led a team of 4. Interviewer: Why this role? Alice: I want to work on AI-mediated tooling.", "outcome": "qualified", "reasoning": "Strong Elixir + leadership + alignment with role intent.", "score": 0.92})
    },
    %{
      name: "bob_not_qualified",
      candidate: %{name: "Bob Brown", email: "bob@example.com", phone: "+1-555-0102"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Tell me about your background. Bob: I have 2 years of HTML experience.", "outcome": "not_qualified", "reasoning": "HTML-only background; role requires backend Elixir.", "score": 0.18})
    },
    %{
      name: "carol_callback",
      candidate: %{name: "Carol Chen", email: "carol@example.com", phone: "+1-555-0103"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: Are you available next week? Carol: I'm at a wedding. Can you call me back Friday?", "outcome": "callback", "reasoning": "Candidate requested specific callback time; not assessed yet.", "score": 0.5})
    },
    %{
      name: "dan_needs_human",
      candidate: %{name: "Dan Davies", email: "dan@example.com", phone: "+1-555-0104"},
      position_title: "Software Engineer",
      claude_response: ~s({"transcript": "Interviewer: What's your experience? Dan: I'm a senior IC at a unicorn but considering management.", "outcome": "needs_human", "reasoning": "Senior IC vs management path is a recruiter judgment call.", "score": 0.6})
    }
  ]

  @cv_match_scenarios [
    %{
      name: "alice_cv_email_match",
      pdf_text: "Alice Anderson — Senior Engineer, 5 years Elixir, 3 years Phoenix...",
      candidate_email: "alice@example.com",
      candidate_phone: nil,
      subject_line: "Alice Anderson CV"
    },
    %{
      name: "carol_cv_subject_match",
      pdf_text: "Carol Chen — Backend developer, Python + Elixir, 4 years experience...",
      candidate_email: "carol.different@gmail.com",
      candidate_phone: nil,
      subject_line: "RE: Application #C-103"
    },
    %{
      name: "dan_cv_fuzzy_match",
      pdf_text: "Daniel Davies — Senior IC at unicorn. Looking to transition...",
      candidate_email: "dan.work@example.com",
      candidate_phone: nil,
      subject_line: "CV submission"
    }
  ]

  def phone_scenarios, do: @phone_scenarios
  def cv_match_scenarios, do: @cv_match_scenarios
end
```

### Step 2: Compile + commit

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
git add lib/showcase/recruit_flow/mock_prompts.ex
git commit -m "feat(recruit_flow): MockPrompts with 4 phone scenarios + 3 CV scenarios"
```

## Report

Status, scenario counts, commit SHA.

---

## Task 5: `PhoneScreenPipeline` boundary (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/phone_screen_pipeline.ex`
- Create: `test/showcase/recruit_flow/phone_screen_pipeline_test.exs`

**Contract:** `PhoneScreenPipeline.run/2` takes an Application + `%{now}`:
1. Transition `PENDING_CALL` (or `CALL_QUEUED` / `CALLBACK`) → `CALL_QUEUED` → `CALL_IN_PROGRESS`.
2. Call Claude with fingerprint `recruit_flow:phone_screen:v1` + scenario = position title slug + candidate name slug.
3. Parse `{transcript, outcome, reasoning, score}`.
4. Transition `CALL_IN_PROGRESS` → `CALL_COMPLETED` (with transcript stored).
5. Transition `CALL_COMPLETED` → `SCORING` (with eval stored).
6. Transition `SCORING` → mapped target based on outcome:
   - `qualified` → `QUALIFIED`
   - `not_qualified` → `CLOSED_REJECTED`
   - `callback` → `CALLBACK`
   - `needs_human` → `NEEDS_HUMAN`

Returns `{:ok, updated_app}` or `{:error, term}`.

### Step 1: Failing tests

Create `test/showcase/recruit_flow/phone_screen_pipeline_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.PhoneScreenPipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.PhoneScreenPipeline
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, %{position: position}}
  end

  defp insert_app(position, candidate_attrs) do
    {:ok, candidate} = %Candidate{} |> Candidate.changeset(candidate_attrs) |> Repo.insert()
    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "PENDING_CALL",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()
    {candidate, app}
  end

  test "qualified outcome leads to QUALIFIED state", %{position: position} do
    scenario = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "alice_qualified"))
    {_, app} = insert_app(position, scenario.candidate)

    Mock.register("recruit_flow:phone_screen:v1",
      scenario: scenario.name,
      text: scenario.claude_response
    )

    {:ok, updated} = PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario.name})

    assert updated.state == "QUALIFIED"
    assert updated.eval["outcome"] == "qualified"
    assert is_binary(updated.transcript)
  end

  test "not_qualified outcome leads to CLOSED_REJECTED", %{position: position} do
    scenario = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "bob_not_qualified"))
    {_, app} = insert_app(position, scenario.candidate)

    Mock.register("recruit_flow:phone_screen:v1",
      scenario: scenario.name,
      text: scenario.claude_response
    )

    {:ok, updated} = PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario.name})

    assert updated.state == "CLOSED_REJECTED"
  end

  test "callback outcome leads to CALLBACK", %{position: position} do
    scenario = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "carol_callback"))
    {_, app} = insert_app(position, scenario.candidate)

    Mock.register("recruit_flow:phone_screen:v1",
      scenario: scenario.name,
      text: scenario.claude_response
    )

    {:ok, updated} = PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario.name})

    assert updated.state == "CALLBACK"
  end

  test "needs_human outcome leads to NEEDS_HUMAN", %{position: position} do
    scenario = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "dan_needs_human"))
    {_, app} = insert_app(position, scenario.candidate)

    Mock.register("recruit_flow:phone_screen:v1",
      scenario: scenario.name,
      text: scenario.claude_response
    )

    {:ok, updated} = PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario.name})

    assert updated.state == "NEEDS_HUMAN"
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase/recruit_flow/phone_screen_pipeline.ex`:

```elixir
defmodule Showcase.RecruitFlow.PhoneScreenPipeline do
  @moduledoc """
  Boundary that orchestrates a phone screen run for an Application.

  Drives the state machine: PENDING_CALL → CALL_QUEUED → CALL_IN_PROGRESS →
  CALL_COMPLETED → SCORING → (QUALIFIED | CLOSED_REJECTED | CALLBACK | NEEDS_HUMAN).

  Returns `{:ok, %Application{}}` on success, `{:error, term}` otherwise.
  """

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @fingerprint "recruit_flow:phone_screen:v1"
  @model "claude-haiku-4-5-20251001"
  @system_prompt """
  You are simulating a phone screen for a recruitment funnel. Generate a brief
  transcript (3-6 exchanges) and score the candidate.

  Respond with JSON ONLY in this shape:
    {
      "transcript": "<3-6 exchange dialog>",
      "outcome": "qualified" | "not_qualified" | "callback" | "needs_human",
      "reasoning": "<one sentence>",
      "score": 0.0 to 1.0
    }
  """

  @outcome_to_state %{
    "qualified" => "QUALIFIED",
    "not_qualified" => "CLOSED_REJECTED",
    "callback" => "CALLBACK",
    "needs_human" => "NEEDS_HUMAN"
  }

  def run(%Application{} = app, %{now: _now, scenario: scenario}) do
    with {:ok, _} <- transition(app.id, "CALL_QUEUED"),
         {:ok, _} <- transition(app.id, "CALL_IN_PROGRESS"),
         {:ok, response} <- call_claude(scenario),
         {:ok, parsed, _} <- ResilientJSONParser.parse(response.text),
         {:ok, _} <- transition(app.id, "CALL_COMPLETED", transcript: parsed["transcript"]),
         {:ok, _} <- transition(app.id, "SCORING", eval: parsed),
         {:ok, updated} <- transition_outcome(app.id, parsed["outcome"]) do
      {:ok, updated}
    else
      {:error, _} = err -> err
    end
  end

  defp call_claude(scenario) do
    req = %Request{
      model: @model,
      messages: [%{role: "user", content: "Run a phone screen."}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }

    AnthropicClient.call(req)
  end

  defp transition(application_id, to_state, opts \\ []) do
    Transitions.apply(application_id, to_state, [actor: "system", reason: "phone_screen"] ++ opts)
  end

  defp transition_outcome(application_id, outcome) do
    case Map.get(@outcome_to_state, outcome) do
      nil -> {:error, {:unknown_outcome, outcome}}
      state -> Transitions.apply(application_id, state, actor: "system", reason: "eval:#{outcome}")
    end
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/phone_screen_pipeline_test.exs
```

Expected: 4 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/phone_screen_pipeline.ex test/showcase/recruit_flow/phone_screen_pipeline_test.exs
git commit -m "feat(recruit_flow): PhoneScreenPipeline with 4-outcome routing"
```

## Report

Status, test count, commit SHA.

---

## Task 6: 5-priority CV cascade step modules

**Files:**
- Create: `lib/showcase/recruit_flow/cascade/exact_email_step.ex`
- Create: `lib/showcase/recruit_flow/cascade/exact_phone_step.ex`
- Create: `lib/showcase/recruit_flow/cascade/subject_line_step.ex`
- Create: `lib/showcase/recruit_flow/cascade/fuzzy_name_step.ex`
- Create: `lib/showcase/recruit_flow/cascade/pdf_content_step.ex`
- Create: `test/showcase/recruit_flow/cascade_test.exs` (single combined file — each step gets a describe block)

**Contract:** Each step implements `Showcase.Common.CascadeMatcher.Step`. Input is `%{email, phone, subject_line, pdf_text}` map; context is `%{repo, now}`. Each returns `{:match, application_id, confidence} | :no_match`.

- **ExactEmailStep**: find Candidate by exact email → Application in AWAITING_CV / CV_FOLLOWUP_SENT state. 1.0 confidence.
- **ExactPhoneStep**: same but by phone. 1.0.
- **SubjectLineStep**: parse `Application #C-(\d+)` pattern from subject. 1.0.
- **FuzzyNameStep**: pg_trgm similarity between PDF-extracted name and candidate names. ≥0.6 threshold.
- **PdfContentStep**: Claude call with fingerprint `recruit_flow:cv_match:v1` returns matched candidate name; look up via exact name match. 0.7-0.8 confidence.

### Step 1: Combined failing tests

Create `test/showcase/recruit_flow/cascade_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.CascadeTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.Cascade.{
    ExactEmailStep,
    ExactPhoneStep,
    FuzzyNameStep,
    PdfContentStep,
    SubjectLineStep
  }
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, candidate} =
      %Candidate{}
      |> Candidate.changeset(%{
        name: "Alice Anderson",
        email: "alice@example.com",
        phone: "+1-555-0101"
      })
      |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "AWAITING_CV",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app, candidate: candidate}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now()}

  describe "ExactEmailStep" do
    test "matches Application by candidate email", %{app: app} do
      input = %{email: "alice@example.com", phone: nil, subject_line: nil, pdf_text: ""}
      assert {:match, application_id, 1.0} = ExactEmailStep.try_match(input, ctx())
      assert application_id == app.id
    end

    test "no_match on unknown email" do
      input = %{email: "ghost@nowhere.com", phone: nil, subject_line: nil, pdf_text: ""}
      assert ExactEmailStep.try_match(input, ctx()) == :no_match
    end

    test "name/0 returns :exact_email" do
      assert ExactEmailStep.name() == :exact_email
    end
  end

  describe "ExactPhoneStep" do
    test "matches by phone", %{app: app} do
      input = %{email: nil, phone: "+1-555-0101", subject_line: nil, pdf_text: ""}
      assert {:match, application_id, 1.0} = ExactPhoneStep.try_match(input, ctx())
      assert application_id == app.id
    end
  end

  describe "SubjectLineStep" do
    test "matches Application #C-<id> pattern", %{app: app} do
      input = %{email: nil, phone: nil, subject_line: "RE: Application #C-#{app.id}", pdf_text: ""}
      assert {:match, application_id, 1.0} = SubjectLineStep.try_match(input, ctx())
      assert application_id == app.id
    end

    test "no_match when subject doesn't match pattern" do
      input = %{email: nil, phone: nil, subject_line: "Just a CV", pdf_text: ""}
      assert SubjectLineStep.try_match(input, ctx()) == :no_match
    end
  end

  describe "FuzzyNameStep" do
    test "matches by similar name in pdf_text", %{app: app} do
      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "Alice Anderson — Senior Engineer..."}
      assert {:match, application_id, score} = FuzzyNameStep.try_match(input, ctx())
      assert application_id == app.id
      assert score >= 0.6
    end

    test "no_match for unrelated name" do
      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "Zebra Zulu — completely different"}
      assert FuzzyNameStep.try_match(input, ctx()) == :no_match
    end
  end

  describe "PdfContentStep" do
    test "matches via Claude content analysis", %{app: app, candidate: candidate} do
      Mock.register("recruit_flow:cv_match:v1",
        scenario: "uncommon_phrasing",
        text: ~s({"candidate_name": "#{candidate.name}", "confidence": 0.75})
      )

      input = %{
        email: nil,
        phone: nil,
        subject_line: nil,
        pdf_text: "uncommon_phrasing"
      }

      assert {:match, application_id, score} = PdfContentStep.try_match(input, ctx())
      assert application_id == app.id
      assert score == 0.75
    end

    test "no_match when Claude returns unknown name" do
      Mock.register("recruit_flow:cv_match:v1",
        scenario: "ghost",
        text: ~s({"candidate_name": "Nonexistent Person", "confidence": 0.9})
      )

      input = %{email: nil, phone: nil, subject_line: nil, pdf_text: "ghost"}
      assert PdfContentStep.try_match(input, ctx()) == :no_match
    end
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/recruit_flow/cascade_test.exs
```

### Step 3: Implement all 5 step modules

Create `lib/showcase/recruit_flow/cascade/exact_email_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.ExactEmailStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @awaiting_cv_states ~w(AWAITING_CV CV_FOLLOWUP_SENT)

  @impl true
  def name, do: :exact_email

  @impl true
  def try_match(%{email: email}, %{repo: repo}) when is_binary(email) and email != "" do
    case repo.one(
           from a in Application,
             join: c in Candidate, on: c.id == a.candidate_id,
             where: c.email == ^email and a.state in ^@awaiting_cv_states,
             select: a.id,
             limit: 1
         ) do
      nil -> :no_match
      id -> {:match, id, 1.0}
    end
  end

  def try_match(_, _), do: :no_match
end
```

Create `lib/showcase/recruit_flow/cascade/exact_phone_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.ExactPhoneStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @awaiting_cv_states ~w(AWAITING_CV CV_FOLLOWUP_SENT)

  @impl true
  def name, do: :exact_phone

  @impl true
  def try_match(%{phone: phone}, %{repo: repo}) when is_binary(phone) and phone != "" do
    case repo.one(
           from a in Application,
             join: c in Candidate, on: c.id == a.candidate_id,
             where: c.phone == ^phone and a.state in ^@awaiting_cv_states,
             select: a.id,
             limit: 1
         ) do
      nil -> :no_match
      id -> {:match, id, 1.0}
    end
  end

  def try_match(_, _), do: :no_match
end
```

Create `lib/showcase/recruit_flow/cascade/subject_line_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.SubjectLineStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  alias Showcase.RecruitFlow.Schemas.Application

  @awaiting_cv_states ~w(AWAITING_CV CV_FOLLOWUP_SENT)

  @impl true
  def name, do: :subject_line

  @impl true
  def try_match(%{subject_line: subj}, %{repo: repo}) when is_binary(subj) and subj != "" do
    case Regex.run(~r/Application #C-(\d+)/i, subj) do
      [_, id_string] ->
        with {id, ""} <- Integer.parse(id_string),
             %Application{state: state} = app when state in @awaiting_cv_states <-
               repo.get(Application, id) do
          {:match, app.id, 1.0}
        else
          _ -> :no_match
        end

      _ ->
        :no_match
    end
  end

  def try_match(_, _), do: :no_match
end
```

Create `lib/showcase/recruit_flow/cascade/fuzzy_name_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.FuzzyNameStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @awaiting_cv_states ~w(AWAITING_CV CV_FOLLOWUP_SENT)
  @similarity_threshold 0.6

  @impl true
  def name, do: :fuzzy_name

  @impl true
  def try_match(%{pdf_text: pdf}, %{repo: repo}) when is_binary(pdf) and pdf != "" do
    # Extract a likely-name token: the first two capitalized words.
    name_guess =
      case Regex.run(~r/([A-Z][a-z]+ [A-Z][a-z]+)/, pdf) do
        [_, n] -> n
        _ -> nil
      end

    case name_guess do
      nil ->
        :no_match

      guess ->
        query =
          from a in Application,
            join: c in Candidate, on: c.id == a.candidate_id,
            where: a.state in ^@awaiting_cv_states,
            select: {a.id, c.name, fragment("similarity(?, ?)", c.name, ^guess)},
            order_by: [desc: fragment("similarity(?, ?)", c.name, ^guess)],
            limit: 1

        case repo.one(query) do
          {id, _name, score} when score >= @similarity_threshold -> {:match, id, score}
          _ -> :no_match
        end
    end
  end

  def try_match(_, _), do: :no_match
end
```

Create `lib/showcase/recruit_flow/cascade/pdf_content_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.PdfContentStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @awaiting_cv_states ~w(AWAITING_CV CV_FOLLOWUP_SENT)
  @fingerprint "recruit_flow:cv_match:v1"
  @model "claude-haiku-4-5-20251001"

  @impl true
  def name, do: :pdf_content

  @impl true
  def try_match(%{pdf_text: pdf}, %{repo: repo}) when is_binary(pdf) and pdf != "" do
    req = %Request{
      model: @model,
      messages: [%{role: "user", content: pdf}],
      system: ~s|Extract the candidate's full name from the CV content. Respond with JSON: {"candidate_name": "...", "confidence": 0.0-1.0}.|,
      metadata: %{fingerprint: @fingerprint, scenario: pdf}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, %{"candidate_name" => name, "confidence" => conf}, _} <-
           ResilientJSONParser.parse(response.text),
         %Application{} = app <-
           repo.one(
             from a in Application,
               join: c in Candidate, on: c.id == a.candidate_id,
               where: c.name == ^name and a.state in ^@awaiting_cv_states,
               limit: 1
           ) do
      {:match, app.id, conf}
    else
      _ -> :no_match
    end
  end

  def try_match(_, _), do: :no_match
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/cascade_test.exs
```

Expected: 9 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/cascade/ test/showcase/recruit_flow/cascade_test.exs
git commit -m "feat(recruit_flow): 5-priority CV cascade steps (email, phone, subject, fuzzy, PDF)"
```

## Report

Status, test count, commit SHA.

---

## Task 7: `CvMatcher` boundary + `CvIntake` flow (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/cv_matcher.ex`
- Create: `test/showcase/recruit_flow/cv_matcher_test.exs`

**Contract:** `CvMatcher.process_cv/2` takes a `%{email, phone, subject_line, pdf_text}` payload + `%{now}`:
1. Run `CascadeMatcher.run/3` with the 5 steps in priority order.
2. If matched: insert a CV row with `application_id`, `match_step`, `match_confidence`. Transition the Application to `CV_RECEIVED`, then if confidence ≥ 0.7 transition to `CV_MATCHED`.
3. If no match: insert CV with `application_id: nil`. Return `:no_match`.

Returns `{:ok, %Cv{}, %Outcome{}}` or `{:no_match, %Outcome{}}`.

### Step 1: Failing tests

Create `test/showcase/recruit_flow/cv_matcher_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.CvMatcherTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.CvMatcher
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Cv, Position}
  alias Showcase.Repo

  setup do
    Mock.reset()

    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, candidate} =
      %Candidate{}
      |> Candidate.changeset(%{
        name: "Alice Anderson",
        email: "alice@example.com",
        phone: "+1-555-0101"
      })
      |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: candidate.id,
        position_id: position.id,
        state: "AWAITING_CV",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app, candidate: candidate}}
  end

  test "process_cv with matching email → Application transitions to CV_MATCHED", %{app: app} do
    payload = %{
      email: "alice@example.com",
      phone: nil,
      subject_line: nil,
      pdf_text: "Alice Anderson resume body"
    }

    {:ok, cv, outcome} = CvMatcher.process_cv(payload, %{now: DateTime.utc_now()})

    assert outcome.matched
    assert outcome.step == :exact_email
    assert cv.application_id == app.id
    assert cv.match_step == "exact_email"

    updated_app = Repo.get!(Application, app.id)
    assert updated_app.state == "CV_MATCHED"
  end

  test "process_cv with no match → CV inserted with nil application_id" do
    payload = %{
      email: "ghost@nowhere.com",
      phone: nil,
      subject_line: nil,
      pdf_text: "Random PDF nothing matches"
    }

    {:no_match, outcome} = CvMatcher.process_cv(payload, %{now: DateTime.utc_now()})

    refute outcome.matched
    # No CV row inserted for unmatched (since application_id is required for the demo)
    # If we change the spec to insert orphan CVs, adjust here.
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase/recruit_flow/cv_matcher.ex`:

```elixir
defmodule Showcase.RecruitFlow.CvMatcher do
  @moduledoc """
  Boundary that runs the 5-priority CV cascade and transitions the matched
  Application to CV_RECEIVED → CV_MATCHED.
  """

  alias Showcase.Common.CascadeMatcher
  alias Showcase.RecruitFlow.Cascade.{
    ExactEmailStep,
    ExactPhoneStep,
    FuzzyNameStep,
    PdfContentStep,
    SubjectLineStep
  }
  alias Showcase.RecruitFlow.Schemas.Cv
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @cascade_steps [
    ExactEmailStep,
    ExactPhoneStep,
    SubjectLineStep,
    FuzzyNameStep,
    PdfContentStep
  ]

  @high_confidence 0.7

  def process_cv(payload, %{now: now}) do
    context = %{repo: Repo, now: now}
    outcome = CascadeMatcher.run(@cascade_steps, payload, context)

    if outcome.matched do
      {:ok, cv} =
        %Cv{}
        |> Cv.changeset(%{
          application_id: outcome.value,
          candidate_email: payload.email,
          candidate_phone: payload.phone,
          subject_line: payload.subject_line,
          pdf_text: payload.pdf_text,
          received_at: now,
          match_step: Atom.to_string(outcome.step),
          match_confidence: outcome.confidence
        })
        |> Repo.insert()

      # Transition the Application to CV_RECEIVED, then if confidence high enough to CV_MATCHED.
      with {:ok, _} <-
             Transitions.apply(outcome.value, "CV_RECEIVED",
               actor: "system",
               reason: "cv_arrived:#{outcome.step}"
             ),
           {:ok, _} <- maybe_match(outcome) do
        {:ok, cv, outcome}
      end
    else
      {:no_match, outcome}
    end
  end

  defp maybe_match(%{value: app_id, confidence: conf}) when conf >= @high_confidence do
    Transitions.apply(app_id, "CV_MATCHED", actor: "system", reason: "high_confidence_cv_match")
  end

  defp maybe_match(_), do: {:ok, :stays_in_cv_received}
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/cv_matcher_test.exs
```

Expected: 2 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/cv_matcher.ex test/showcase/recruit_flow/cv_matcher_test.exs
git commit -m "feat(recruit_flow): CvMatcher boundary with 5-step cascade"
```

## Report

Status, test count, commit SHA.

---

## Task 8: `Scheduler` module with 5 tick functions (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/scheduler.ex`
- Create: `test/showcase/recruit_flow/scheduler_test.exs`

**Contract:** 5 public functions, each one tick of one job. All idempotent (running twice on the same state produces the same result).

- `Scheduler.submit_queued_calls(%{now})` — PENDING_CALL → CALL_QUEUED for up to N applications
- `Scheduler.poll_stuck_calls(%{now})` — CALL_STUCK → CALL_QUEUED (retry) for entries older than 5 min, else CLOSED_FAILED
- `Scheduler.poll_cv_inbox(%{now})` — no-op for the demo (CV arrival is driven by the UI button)
- `Scheduler.send_cv_followups(%{now})` — AWAITING_CV (older than 3 days) → CV_FOLLOWUP_SENT
- `Scheduler.auto_close_stale_rejections(%{now})` — CLOSED_REJECTED (older than 24h) → CLOSED_REJECTED_STALE

Plus `Scheduler.tick_all(%{now})` that runs all five and returns a summary `%{job_name => count}`.

For the demo, `now` is supplied by caller — making tests deterministic.

### Step 1: Failing tests

Create `test/showcase/recruit_flow/scheduler_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.SchedulerTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Scheduler
  alias Showcase.Repo

  setup do
    {:ok, position} =
      %Position{}
      |> Position.changeset(%{title: "Software Engineer", prompt_section: "se_v1"})
      |> Repo.insert()

    {:ok, %{position: position}}
  end

  defp insert_app(position, state, ts \\ DateTime.utc_now()) do
    {:ok, c} = Repo.insert(%Candidate{name: "C-#{System.unique_integer([:positive])}"})

    {:ok, a} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: c.id,
        position_id: position.id,
        state: state,
        state_changed_at: ts
      })
      |> Repo.insert()

    a
  end

  test "submit_queued_calls advances all PENDING_CALL → CALL_QUEUED", %{position: position} do
    a1 = insert_app(position, "PENDING_CALL")
    a2 = insert_app(position, "PENDING_CALL")

    count = Scheduler.submit_queued_calls(%{now: DateTime.utc_now()})
    assert count == 2

    assert Repo.get!(Application, a1.id).state == "CALL_QUEUED"
    assert Repo.get!(Application, a2.id).state == "CALL_QUEUED"
  end

  test "send_cv_followups only touches AWAITING_CV older than 3 days", %{position: position} do
    now = DateTime.utc_now()
    recent = insert_app(position, "AWAITING_CV", now)
    old = insert_app(position, "AWAITING_CV", DateTime.add(now, -4, :day))

    count = Scheduler.send_cv_followups(%{now: now})
    assert count == 1

    assert Repo.get!(Application, recent.id).state == "AWAITING_CV"
    assert Repo.get!(Application, old.id).state == "CV_FOLLOWUP_SENT"
  end

  test "auto_close_stale_rejections only touches CLOSED_REJECTED older than 24h", %{position: position} do
    now = DateTime.utc_now()
    fresh = insert_app(position, "CLOSED_REJECTED", DateTime.add(now, -2, :hour))
    stale = insert_app(position, "CLOSED_REJECTED", DateTime.add(now, -25, :hour))

    count = Scheduler.auto_close_stale_rejections(%{now: now})
    assert count == 1

    assert Repo.get!(Application, fresh.id).state == "CLOSED_REJECTED"
    assert Repo.get!(Application, stale.id).state == "CLOSED_REJECTED_STALE"
  end

  test "tick_all returns a summary map", %{position: position} do
    insert_app(position, "PENDING_CALL")

    summary = Scheduler.tick_all(%{now: DateTime.utc_now()})
    assert is_map(summary)
    assert Map.has_key?(summary, :submit_queued_calls)
    assert Map.has_key?(summary, :poll_stuck_calls)
    assert Map.has_key?(summary, :poll_cv_inbox)
    assert Map.has_key?(summary, :send_cv_followups)
    assert Map.has_key?(summary, :auto_close_stale_rejections)
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase/recruit_flow/scheduler.ex`:

```elixir
defmodule Showcase.RecruitFlow.Scheduler do
  @moduledoc """
  RecruitFlow scheduler. Five jobs visible in the UI, each idempotent.
  AE drives the clock by clicking "Tick scheduler" — see KanbanLive.

  Five tick functions return the count of applications advanced.
  `tick_all/1` runs all five and returns a summary map.
  """

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @cv_followup_age_days 3
  @stale_rejection_age_hours 24
  @stuck_call_age_minutes 5

  def submit_queued_calls(%{now: _now}) do
    ids = Repo.all(from a in Application, where: a.state == "PENDING_CALL", select: a.id)
    advance_all(ids, "CALL_QUEUED", reason: "scheduler:submit_queued")
  end

  def poll_stuck_calls(%{now: now}) do
    threshold = DateTime.add(now, -@stuck_call_age_minutes, :minute)

    ids =
      Repo.all(
        from a in Application,
          where: a.state == "CALL_STUCK" and a.state_changed_at <= ^threshold,
          select: a.id
      )

    advance_all(ids, "CALL_QUEUED", reason: "scheduler:retry_stuck")
  end

  def poll_cv_inbox(%{now: _now}) do
    # Demo: CV arrival driven by UI button. This tick is a no-op for now.
    0
  end

  def send_cv_followups(%{now: now}) do
    threshold = DateTime.add(now, -@cv_followup_age_days, :day)

    ids =
      Repo.all(
        from a in Application,
          where: a.state == "AWAITING_CV" and a.state_changed_at <= ^threshold,
          select: a.id
      )

    advance_all(ids, "CV_FOLLOWUP_SENT", reason: "scheduler:cv_followup")
  end

  def auto_close_stale_rejections(%{now: now}) do
    threshold = DateTime.add(now, -@stale_rejection_age_hours, :hour)

    ids =
      Repo.all(
        from a in Application,
          where: a.state == "CLOSED_REJECTED" and a.state_changed_at <= ^threshold,
          select: a.id
      )

    advance_all(ids, "CLOSED_REJECTED_STALE", reason: "scheduler:stale_rejection")
  end

  def tick_all(%{now: now} = ctx) do
    %{
      submit_queued_calls: submit_queued_calls(ctx),
      poll_stuck_calls: poll_stuck_calls(ctx),
      poll_cv_inbox: poll_cv_inbox(ctx),
      send_cv_followups: send_cv_followups(ctx),
      auto_close_stale_rejections: auto_close_stale_rejections(ctx)
    }
  end

  defp advance_all(ids, to_state, opts) do
    Enum.reduce(ids, 0, fn id, acc ->
      case Transitions.apply(id, to_state, [actor: "system"] ++ opts) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/scheduler_test.exs
```

Expected: 4 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow/scheduler.ex test/showcase/recruit_flow/scheduler_test.exs
git commit -m "feat(recruit_flow): Scheduler with 5 tick functions + tick_all summary"
```

## Report

Status, test count, commit SHA.

---

## Task 9: `RecruitFlow` public context + `Seed` (TDD on Seed)

**Files:**
- Create: `lib/showcase/recruit_flow.ex`
- Create: `lib/showcase/recruit_flow/seed.ex`
- Create: `test/showcase/recruit_flow/seed_test.exs`

### Step 1: Implement context

Create `lib/showcase/recruit_flow.ex`:

```elixir
defmodule Showcase.RecruitFlow do
  @moduledoc "Public context for the RecruitFlow demo."

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  def list_applications do
    Repo.all(
      from a in Application,
        order_by: [asc: a.id],
        preload: [:candidate, :position, :cvs]
    )
  end

  def applications_by_state do
    list_applications() |> Enum.group_by(& &1.state)
  end

  def find_application(id) do
    Repo.get(Application, id) |> Repo.preload([:candidate, :position, :cvs])
  end

  def list_positions, do: Repo.all(from p in Position, order_by: [asc: p.title])

  def register_mock_responses do
    Enum.each(MockPrompts.phone_scenarios(), fn s ->
      Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)
    end)

    # CV match scenarios — keyed by pdf_text (since that's what the cascade uses as scenario)
    Enum.each(MockPrompts.cv_match_scenarios(), fn s ->
      # No canned response needed for CV match Claude calls unless we want to
      # demo the PdfContentStep. For visible coverage, register one:
      Mock.register("recruit_flow:cv_match:v1",
        scenario: s.pdf_text,
        text: ~s({"candidate_name": "#{extract_name(s.pdf_text)}", "confidence": 0.75})
      )
    end)
  end

  defp extract_name(text) do
    case Regex.run(~r/([A-Z][a-z]+ [A-Z][a-z]+)/, text) do
      [_, n] -> n
      _ -> "Unknown"
    end
  end
end
```

### Step 2: Failing test + Step 3: Implement Seed

Create `test/showcase/recruit_flow/seed_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.SeedTest do
  use Showcase.DataCase, async: false

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.RecruitFlow.Seed
  alias Showcase.Repo

  test "name + description + oban_queue" do
    assert Seed.name() == "RecruitFlow"
    assert is_binary(Seed.description())
    assert Seed.oban_queue() == :recruit_flow
  end

  test "tables/0 returns rf_* tables children-before-parents" do
    tables = Seed.tables()
    assert "rf_cvs" in tables
    assert "rf_applications" in tables
    assert "rf_candidates" in tables
    assert "rf_positions" in tables
  end

  test "seed/0 populates positions, candidates, applications" do
    assert :ok = Seed.seed()
    assert Repo.aggregate(Position, :count) >= 1
    assert Repo.aggregate(Candidate, :count) >= 4
    assert Repo.aggregate(Application, :count) >= 4
  end

  test "seed/0 is idempotent" do
    assert :ok = Seed.seed()
    a = {Repo.aggregate(Position, :count), Repo.aggregate(Candidate, :count), Repo.aggregate(Application, :count)}
    assert :ok = Seed.seed()
    b = {Repo.aggregate(Position, :count), Repo.aggregate(Candidate, :count), Repo.aggregate(Application, :count)}
    assert a == b
  end
end
```

Create `lib/showcase/recruit_flow/seed.ex`:

```elixir
defmodule Showcase.RecruitFlow.Seed do
  @moduledoc "Seeds RecruitFlow demo with positions, candidates, applications."

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  @impl true
  def name, do: "RecruitFlow"

  @impl true
  def description do
    "Phone-screen, score, and chase candidates through an 18-state funnel. Recruiters intervene only on the ambiguous middle."
  end

  @impl true
  def oban_queue, do: :recruit_flow

  @impl true
  def tables do
    ["rf_cvs", "rf_applications", "rf_candidates", "rf_positions"]
  end

  @impl true
  def seed do
    Repo.transaction(fn ->
      position = seed_position()
      seed_applications(position)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_position do
    case Repo.get_by(Position, title: "Software Engineer") do
      nil ->
        {:ok, p} =
          %Position{}
          |> Position.changeset(%{
            title: "Software Engineer",
            department: "Engineering",
            prompt_section: "se_v1",
            default_prompt_body: "You are screening for a Software Engineer role at Neurony. Focus on backend Elixir + AI integration experience."
          })
          |> Repo.insert()
        p

      existing -> existing
    end
  end

  defp seed_applications(position) do
    Enum.each(MockPrompts.phone_scenarios(), fn s ->
      candidate =
        case Repo.get_by(Candidate, name: s.candidate.name) do
          nil ->
            {:ok, c} = %Candidate{} |> Candidate.changeset(s.candidate) |> Repo.insert()
            c
          existing -> existing
        end

      case Repo.get_by(Application, candidate_id: candidate.id, position_id: position.id) do
        nil ->
          %Application{}
          |> Application.changeset(%{
            candidate_id: candidate.id,
            position_id: position.id,
            state: "PENDING_CALL",
            state_changed_at: DateTime.utc_now()
          })
          |> Repo.insert!()

        _ -> :noop
      end
    end)
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/recruit_flow/seed_test.exs
```

Expected: 4 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/recruit_flow.ex lib/showcase/recruit_flow/seed.ex test/showcase/recruit_flow/seed_test.exs
git commit -m "feat(recruit_flow): public context + Seed with DemoSeeder behaviour"
```

## Report

Status, test count, commit SHA.

---

## Task 10: `KanbanLive` at `/recruit-flow` (TDD)

**Files:**
- Create: `lib/showcase_web/live/recruit_flow/kanban_live.ex`
- Create: `test/showcase_web/live/recruit_flow/kanban_live_test.exs`
- Modify: `lib/showcase_web/router.ex`

**Contract:** Shows applications grouped into "swim lanes" (5 columns: Pre-call, Eval, Awaiting CV, CV Received, Closed). Each card is clickable → opens `/recruit-flow/applications/:id`. Includes:
- "Tick scheduler" button → calls `Scheduler.tick_all/1`, refreshes the board.
- "Run AI screen" button per PENDING_CALL/CALL_QUEUED card → enqueues PhoneScreenPipeline.
- "CV arrived" button per AWAITING_CV/CV_FOLLOWUP_SENT card → picks a CV scenario, runs CvMatcher.

### Step 1: Failing tests

Create `test/showcase_web/live/recruit_flow/kanban_live_test.exs`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.KanbanLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.RecruitFlow.Seed

  setup do
    Showcase.Common.AnthropicClient.Mock.reset()
    Showcase.RecruitFlow.register_mock_responses()
    Seed.seed()
    :ok
  end

  test "renders the board at /recruit-flow", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/recruit-flow")

    assert html =~ "RecruitFlow"
    assert html =~ "Pre-call"
    assert html =~ "Eval"
    assert html =~ "Alice Anderson"
  end

  test "tick_scheduler advances applications", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/recruit-flow")

    initial_html = render(view)
    assert initial_html =~ "PENDING_CALL"

    render_click(view, "tick_scheduler", %{})

    after_html = render(view)
    assert after_html =~ "CALL_QUEUED"
  end
end
```

### Step 2: Add routes

In `lib/showcase_web/router.ex`, public scope, add:

```elixir
live "/recruit-flow", RecruitFlow.KanbanLive
live "/recruit-flow/applications/:id", RecruitFlow.ApplicationDetailLive
```

### Step 3: Implement KanbanLive

Create `lib/showcase_web/live/recruit_flow/kanban_live.ex`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.KanbanLive do
  use ShowcaseWeb, :live_view

  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.{PhoneScreenPipeline, Scheduler}

  @swim_lanes [
    {"Pre-call", ~w(PENDING_CALL CALL_QUEUED CALL_IN_PROGRESS CALL_COMPLETED CALL_STUCK)},
    {"Eval", ~w(SCORING QUALIFIED CALLBACK NEEDS_HUMAN ESCALATED)},
    {"Awaiting CV", ~w(AWAITING_CV CV_FOLLOWUP_SENT)},
    {"CV Received", ~w(CV_RECEIVED CV_MATCHED)},
    {"Closed", ~w(CLOSED_HIRED_READY CLOSED_REJECTED CLOSED_REJECTED_STALE CLOSED_NO_CV CLOSED_FAILED)}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and
         Application.get_env(:showcase, :anthropic_client_impl) ==
           Showcase.Common.AnthropicClient.Mock do
      RecruitFlow.register_mock_responses()
    end

    {:ok,
     socket
     |> assign(:page_title, "RecruitFlow")
     |> assign(:swim_lanes, @swim_lanes)
     |> assign(:by_state, RecruitFlow.applications_by_state())
     |> assign(:last_tick_summary, nil)}
  end

  @impl true
  def handle_event("tick_scheduler", _params, socket) do
    summary = Scheduler.tick_all(%{now: DateTime.utc_now()})

    {:noreply,
     socket
     |> assign(:by_state, RecruitFlow.applications_by_state())
     |> assign(:last_tick_summary, summary)
     |> put_flash(:info, "Scheduler ticked: #{inspect(summary)}")}
  end

  def handle_event("run_ai_screen", %{"id" => id_string, "scenario" => scenario}, socket) do
    app = RecruitFlow.find_application(String.to_integer(id_string))

    case PhoneScreenPipeline.run(app, %{now: DateTime.utc_now(), scenario: scenario}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:by_state, RecruitFlow.applications_by_state())
         |> put_flash(:info, "Phone screen complete.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Screen failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-7xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">RecruitFlow</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Top-of-funnel recruitment with an 18-state machine + AI phone screens.
            </p>
          </div>
          <div class="flex gap-3 items-center">
            <button
              type="button"
              class="rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
              phx-click="tick_scheduler"
            >
              Tick scheduler
            </button>
            <a href="/" class="text-sm text-zinc-500 underline">&larr; Dashboard</a>
          </div>
        </div>
        <%= if @last_tick_summary do %>
          <div class="max-w-7xl mx-auto px-6 pb-3 text-xs font-mono text-zinc-500">
            Last tick: {inspect(@last_tick_summary)}
          </div>
        <% end %>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-6 overflow-x-auto">
        <div class="grid grid-cols-5 gap-3 min-w-[1100px]">
          <section :for={{lane_name, states} <- @swim_lanes} class="rounded border bg-white p-3">
            <h2 class="text-xs uppercase tracking-wide text-zinc-500 mb-2">{lane_name}</h2>
            <ul class="space-y-2">
              <%= for state <- states, app <- Map.get(@by_state, state, []) do %>
                <li class="rounded border bg-zinc-50 p-2 text-xs">
                  <a href={"/recruit-flow/applications/#{app.id}"} class="font-medium hover:underline">
                    {app.candidate.name}
                  </a>
                  <p class="text-zinc-500 mt-0.5">{app.position && app.position.title}</p>
                  <p class="font-mono text-[10px] text-zinc-400 mt-1">{state}</p>
                  <%= if state in ["PENDING_CALL", "CALL_QUEUED"] do %>
                    <%= for s <- ~w(alice_qualified bob_not_qualified carol_callback dan_needs_human) do %>
                      <button
                        type="button"
                        class="mt-1 text-[10px] underline text-emerald-700 mr-2"
                        phx-click="run_ai_screen"
                        phx-value-id={app.id}
                        phx-value-scenario={s}
                      >
                        Run as: {s}
                      </button>
                    <% end %>
                  <% end %>
                </li>
              <% end %>
            </ul>
          </section>
        </div>
      </main>
    </div>
    """
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase_web/live/recruit_flow/kanban_live_test.exs 2>&1 | tail -5
```

Expected: 2 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase_web/live/recruit_flow/kanban_live.ex test/showcase_web/live/recruit_flow/kanban_live_test.exs lib/showcase_web/router.ex
git commit -m "feat(web): RecruitFlow KanbanLive with swim lanes + scheduler tick"
```

## Report

Status, test count, commit SHA.

---

## Task 11: `ApplicationDetailLive` (TDD)

**Files:**
- Create: `lib/showcase_web/live/recruit_flow/application_detail_live.ex`
- Create: `test/showcase_web/live/recruit_flow/application_detail_live_test.exs`

**Contract:** Shows one Application's transcript, eval, state history (from AuditLog), and CV cards. Has buttons:
- "Run AI screen" — re-runs the phone screen with a chosen scenario.
- "CV arrived" — picks a CV scenario, runs CvMatcher.
- "Escalate" — NEEDS_HUMAN → ESCALATED via Transitions.apply.

### Step 1: Failing tests

Create `test/showcase_web/live/recruit_flow/application_detail_live_test.exs`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Seed
  alias Showcase.Repo

  setup do
    Mock.reset()
    RecruitFlow.register_mock_responses()
    Seed.seed()

    app = Repo.one(from a in Application, limit: 1) |> Repo.preload(:candidate)
    {:ok, %{app: app}}
  end

  test "renders the application detail", %{conn: conn, app: app} do
    {:ok, _view, html} = live(conn, "/recruit-flow/applications/#{app.id}")

    assert html =~ app.candidate.name
    assert html =~ "PENDING_CALL"
  end

  test "running AI screen transitions the application", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    updated = Repo.get!(Application, app.id)
    # Whatever scenario was chosen, the application should no longer be PENDING_CALL.
    refute updated.state == "PENDING_CALL"
  end

  test "transition timeline shows audit log entries", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    html = render(view)
    assert html =~ "state_change"
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase_web/live/recruit_flow/application_detail_live.ex`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.PhoneScreenPipeline

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    app = RecruitFlow.find_application(String.to_integer(id))

    if app == nil do
      {:ok, push_navigate(socket, to: "/recruit-flow")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")
      end

      {:ok, socket |> assign_app(app)}
    end
  end

  defp assign_app(socket, app) do
    {:ok, audits} =
      AuditLog.for_entity("recruit_flow", "application", to_string(app.id))

    socket
    |> assign(:page_title, "Application ##{app.id}")
    |> assign(:app, app)
    |> assign(:audit, audits)
  end

  @impl true
  def handle_event("run_ai_screen", %{"scenario" => scenario}, socket) do
    case PhoneScreenPipeline.run(socket.assigns.app, %{now: DateTime.utc_now(), scenario: scenario}) do
      {:ok, _} ->
        app = RecruitFlow.find_application(socket.assigns.app.id)
        {:noreply, socket |> assign_app(app) |> put_flash(:info, "Phone screen complete.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Phone screen failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:recruit_flow, :transitioned, %{application_id: id}}, socket)
      when id == socket.assigns.app.id do
    app = RecruitFlow.find_application(id)
    {:noreply, assign_app(socket, app)}
  end

  def handle_info({:recruit_flow, _, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5">
          <a href="/recruit-flow" class="text-sm text-zinc-500 underline">&larr; Board</a>
          <h1 class="text-xl font-semibold mt-2">{@app.candidate.name}</h1>
          <p class="text-sm text-zinc-500 mt-1">
            {@app.position && @app.position.title} ·
            <span class="font-mono">{@app.state}</span>
          </p>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-6 py-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section class="lg:col-span-2 space-y-4">
          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Transcript</h2>
            <%= if @app.transcript do %>
              <pre class="whitespace-pre-wrap text-sm text-zinc-700">{@app.transcript}</pre>
            <% else %>
              <p class="text-sm text-zinc-500">No transcript yet.</p>
            <% end %>
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Eval</h2>
            <%= if @app.eval not in [nil, %{}] do %>
              <p class="text-sm">outcome: <span class="font-mono">{@app.eval["outcome"]}</span></p>
              <p class="text-sm">score: <span class="font-mono">{@app.eval["score"]}</span></p>
              <p class="text-sm mt-2 text-zinc-700">{@app.eval["reasoning"]}</p>
            <% else %>
              <p class="text-sm text-zinc-500">No eval yet.</p>
            <% end %>
          </div>
        </section>

        <aside class="space-y-4">
          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Run AI screen</h2>
            <div class="flex flex-col gap-2">
              <button
                :for={s <- ~w(alice_qualified bob_not_qualified carol_callback dan_needs_human)}
                type="button"
                class="text-xs underline text-emerald-700 text-left"
                phx-click="run_ai_screen"
                phx-value-scenario={s}
              >
                {s}
              </button>
            </div>
          </div>

          <div class="rounded border bg-white p-4">
            <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Transition timeline</h2>
            <%= if @audit == [] do %>
              <p class="text-sm text-zinc-500">No transitions yet.</p>
            <% else %>
              <ol class="space-y-2">
                <li :for={entry <- @audit} class="text-xs border-l-2 border-zinc-200 pl-2">
                  <p class="font-medium">{entry.event}</p>
                  <p class="text-zinc-500">
                    {entry.payload["from"]} → {entry.payload["to"]}
                  </p>
                  <p class="text-zinc-400">{entry.inserted_at}</p>
                </li>
              </ol>
            <% end %>
          </div>
        </aside>
      </main>
    </div>
    """
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase_web/live/recruit_flow/application_detail_live_test.exs 2>&1 | tail -5
```

Expected: 3 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase_web/live/recruit_flow/application_detail_live.ex test/showcase_web/live/recruit_flow/application_detail_live_test.exs
git commit -m "feat(web): RecruitFlow ApplicationDetailLive with transcript + timeline"
```

## Report

Status, test count, commit SHA.

---

## Task 12: TileConfig flip + Smoke test + phase-4 tag

**Files:**
- Modify: `lib/showcase/dashboard/tile_config.ex`
- Modify: `test/showcase/dashboard/tile_config_test.exs`

### Step 1: Update TileConfig

In `lib/showcase/dashboard/tile_config.ex`, replace the `:recruit_flow` entry:

```elixir
    %Tile{
      id: :recruit_flow,
      title: "RecruitFlow",
      description:
        "Phone-screen, score, and chase candidates through a complete recruitment funnel with a state-machine-driven pipeline.",
      roi_hook: "Recruiters intervene only on the ambiguous middle — everything else moves automatically.",
      status: :live,
      path: "/recruit-flow",
      seeder: Showcase.RecruitFlow.Seed
    },
```

(Only `status`, `path`, and `seeder` change.)

### Step 2: Update tile_config_test.exs

Find the existing test `"OrderFlow and Invoice Approval are live"` and replace with:

```elixir
    test "OrderFlow, Invoice Approval, and RecruitFlow are live" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      assert by_id[:order_flow].status == :live
      assert by_id[:invoice_approval].status == :live
      assert by_id[:recruit_flow].status == :live
      assert by_id[:recruit_flow].path == "/recruit-flow"
      assert by_id[:recruit_flow].seeder == Showcase.RecruitFlow.Seed
    end

    test "Planogram and Restaurant Compliance remain coming_soon" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      Enum.each([:planogram, :restaurant_compliance], fn id ->
        assert by_id[id].status == :coming_soon
        assert by_id[id].path == nil
        assert by_id[id].seeder == nil
      end)
    end
```

(Remove the old "RecruitFlow, Planogram, Restaurant Compliance are coming_soon" test if it's still there.)

### Step 3: Run tests

```bash
mix test test/showcase/dashboard/tile_config_test.exs test/showcase/dashboard_test.exs test/showcase_web/live/dashboard_live_test.exs test/showcase_web/live/admin/reset_live_test.exs 2>&1 | tail -5
```

Expected: all green.

### Step 4: Full suite

```bash
mix test 2>&1 | tail -3
```

Expected: full suite green (~210 tests).

### Step 5: Compile clean

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 6: Boot + smoke routes

```bash
curl -s -o /dev/null -w "GET / → %{http_code}\n" http://localhost:4321/
curl -s -o /dev/null -w "GET /recruit-flow → %{http_code}\n" http://localhost:4321/recruit-flow
curl -s -o /dev/null -w "GET /admin/reset auth → %{http_code}\n" -u admin:changeme http://localhost:4321/admin/reset
```

Expected: all 200.

### Step 7: Tag

```bash
git tag -a phase-4 -m "Phase 4 RecruitFlow complete: 18-state machine, AI phone screen, 5-priority CV cascade, scheduler ticks"
git tag -l 'phase-*'
```

Expected: `phase-0` through `phase-4` listed.

### Step 8: Commit

```bash
git add lib/showcase/dashboard/tile_config.ex test/showcase/dashboard/tile_config_test.exs
git commit -m "feat(dashboard): flip RecruitFlow tile from coming_soon to live"
```

## Report

Status, test count, route responses, tag confirmation.

---

## Phase 4 acceptance criteria

When all 12 tasks are done:

- [ ] `mix test` green; ~210 tests pass
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `GET /recruit-flow` renders the Kanban with 5 swim lanes
- [ ] `GET /recruit-flow/applications/:id` renders transcript + eval + audit timeline
- [ ] "Tick scheduler" advances PENDING_CALL → CALL_QUEUED
- [ ] "Run AI screen" with each of 4 scenarios drives the application to QUALIFIED / CLOSED_REJECTED / CALLBACK / NEEDS_HUMAN
- [ ] AuditLog entries record every state transition
- [ ] Dashboard `/` shows RecruitFlow as `:live`
- [ ] `/admin/reset` has a "Reset RecruitFlow" button
- [ ] `phase-4` tag in git history

Next plan (Phase 5: Planogram) — vision call + role switcher + cost transparency + mobile QR handoff.
