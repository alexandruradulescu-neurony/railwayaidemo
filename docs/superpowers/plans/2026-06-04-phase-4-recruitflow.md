# Phase 4: RecruitFlow Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the RecruitFlow demo end-to-end. A Kanban board with 5 columns visualizes every Application's state. AE clicks "Run AI screen" → Claude generates a synthetic phone transcript and routes the Application via a 4-outcome eval; "CV arrived" runs the 5-priority CV cascade to match a CV to a QUALIFIED Application. Every state transition writes a `Common.AuditLog` entry.

**Architecture:** Plain Ecto schemas under `rf_*` prefix. Application state is one of **5 values: PENDING / QUALIFIED / HIRED / REJECTED / NEEDS_HUMAN**. Pure `StateMachine` module defines the 5-state transition table. Pure `Transitions` boundary wraps state changes with `AuditLog` writes. `PhoneScreenPipeline` runs Claude → maps outcome → transitions Application. `CvMatcher` reuses `Showcase.Common.CascadeMatcher` with 5 RecruitFlow-specific step modules. One scheduler tick (`auto_close_stale_qualified`) demonstrates the scheduler-pattern teaching point without bloat. Two LiveViews: `KanbanLive` at `/recruit-flow`, `ApplicationDetailLive` at `/recruit-flow/applications/:id`.

**Tech Stack:**
- Builds on `main` after Phase 3 merge (HEAD `07d9c2e`, tags `phase-0` through `phase-3`)
- Plain Ecto, JSONB for transcript / eval, no per-line item tables
- `Showcase.Common.AnthropicClient` (Mock in tests) with fingerprints `recruit_flow:phone_screen:v1` + `recruit_flow:cv_match:v1`
- `Showcase.Common.ResilientJSONParser`, `Showcase.Common.AuditLog`, `Showcase.Common.CascadeMatcher`
- LiveView + Phoenix.PubSub for per-application live updates

**Reference spec:** `docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md` §4.2

**Design simplification note:** the spec brief mentions an 18-state machine. Per project preference (logged 2026-06-04), the implementation uses **5 states** — the minimum that retains a recognizable funnel: PENDING → (QUALIFIED → HIRED) | REJECTED | NEEDS_HUMAN. Callback outcomes don't get their own state; they leave the Application in PENDING with an audit-log entry noting the callback request. Scheduler is one tick, not five.

---

## File structure

```
lib/showcase/
  recruit_flow.ex                                  # public context
  recruit_flow/
    schemas/
      position.ex                                  # rf_positions
      candidate.ex                                 # rf_candidates
      application.ex                               # rf_applications (state ∈ 5)
      cv.ex                                        # rf_cvs
    impl/
      state_machine.ex                             # 5 states + transition table
    transitions.ex                                 # boundary: apply/3 with audit
    cascade/
      exact_email_step.ex
      exact_phone_step.ex
      subject_line_step.ex
      fuzzy_name_step.ex
      pdf_content_step.ex
    phone_screen_pipeline.ex                       # boundary: Claude → transition
    cv_matcher.ex                                  # boundary: cascade → QUALIFIED → HIRED
    scheduler.ex                                   # one tick: auto_close_stale_qualified
    mock_prompts.ex                                # canned phone + CV responses
    seed.ex                                        # DemoSeeder

  showcase_web/live/recruit_flow/
    kanban_live.ex
    application_detail_live.ex

  showcase/dashboard/tile_config.ex                # MODIFY: flip recruit_flow to :live

priv/repo/migrations/
  <ts>_create_recruit_flow_schemas.exs

test/
  showcase/recruit_flow/
    impl/state_machine_test.exs
    transitions_test.exs
    cascade_test.exs                               # 5 steps in one file
    phone_screen_pipeline_test.exs
    cv_matcher_test.exs
    scheduler_test.exs
    seed_test.exs
  showcase_web/live/recruit_flow/
    kanban_live_test.exs
    application_detail_live_test.exs
```

---

## Task 1: Schemas + migration

**Files:**
- Create: `lib/showcase/recruit_flow/schemas/{position,candidate,application,cv}.ex`
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
      add :prompt_section, :string, null: false
      add :default_prompt_body, :text
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
      add :state, :string, null: false, default: "PENDING"
      add :transcript, :text
      add :eval, :map, default: %{}
      add :state_changed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rf_applications, [:candidate_id, :position_id])
    create index(:rf_applications, [:state])

    create table(:rf_cvs) do
      add :application_id, references(:rf_applications, on_delete: :delete_all)
      add :candidate_email, :string
      add :candidate_phone, :string
      add :subject_line, :string
      add :pdf_text, :text, null: false
      add :received_at, :utc_datetime_usec, null: false
      add :match_step, :string
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
    field :state, :string, default: "PENDING"
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

### Step 7: Run migration + verify + commit

```bash
mix ecto.migrate
mix compile --warnings-as-errors
PGPASSWORD=postgres psql -U postgres -h localhost -d showcase_dev -c "\dt rf_*" 2>&1 | tail -10
mix test 2>&1 | tail -3

git add lib/showcase/recruit_flow/schemas/ priv/repo/migrations/
git commit -m "feat(recruit_flow): schemas + migration for rf_* tables"
```

Expected: 4 rf_* tables, compile clean, tests unchanged (171 + 1 property).

## Report

Status, files, migration filename, test count, commit SHA.

---

## Task 2: `StateMachine` — 5 states + transition table (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/impl/state_machine.ex`
- Create: `test/showcase/recruit_flow/impl/state_machine_test.exs`

**The 5 states:**

| State | Meaning |
|---|---|
| `PENDING` | Initial. AI screen not yet run, or callback requested. |
| `QUALIFIED` | AI screen positive, awaiting CV. |
| `HIRED` | CV matched (terminal — handoff to recruiter). |
| `REJECTED` | AI screen negative (terminal). |
| `NEEDS_HUMAN` | AI uncertain (terminal — escalated to human review). |

**Transitions:**
- `PENDING` → `QUALIFIED` | `REJECTED` | `NEEDS_HUMAN` (from AI screen outcomes)
- `PENDING` → `PENDING` (callback outcome — same state, but audit entry logged)
- `QUALIFIED` → `HIRED` (CV matched via cascade)
- `QUALIFIED` → `REJECTED` (stale, auto-closed by scheduler)
- Terminal states have no outgoing transitions.

### Step 1: Failing tests

Create `test/showcase/recruit_flow/impl/state_machine_test.exs`:

```elixir
defmodule Showcase.RecruitFlow.Impl.StateMachineTest do
  use ExUnit.Case, async: true

  alias Showcase.RecruitFlow.Impl.StateMachine

  describe "states/0" do
    test "returns exactly 5 states" do
      assert length(StateMachine.states()) == 5
    end

    test "includes PENDING, QUALIFIED, HIRED, REJECTED, NEEDS_HUMAN" do
      states = StateMachine.states()
      assert "PENDING" in states
      assert "QUALIFIED" in states
      assert "HIRED" in states
      assert "REJECTED" in states
      assert "NEEDS_HUMAN" in states
    end
  end

  describe "allowed?/2" do
    test "PENDING → QUALIFIED is allowed" do
      assert StateMachine.allowed?("PENDING", "QUALIFIED")
    end

    test "PENDING → REJECTED is allowed" do
      assert StateMachine.allowed?("PENDING", "REJECTED")
    end

    test "PENDING → NEEDS_HUMAN is allowed" do
      assert StateMachine.allowed?("PENDING", "NEEDS_HUMAN")
    end

    test "PENDING → PENDING is allowed (callback re-queue)" do
      assert StateMachine.allowed?("PENDING", "PENDING")
    end

    test "PENDING → HIRED is not allowed (must go through QUALIFIED)" do
      refute StateMachine.allowed?("PENDING", "HIRED")
    end

    test "QUALIFIED → HIRED is allowed" do
      assert StateMachine.allowed?("QUALIFIED", "HIRED")
    end

    test "QUALIFIED → REJECTED is allowed (auto-close stale)" do
      assert StateMachine.allowed?("QUALIFIED", "REJECTED")
    end

    test "terminal states have no outgoing" do
      refute StateMachine.allowed?("HIRED", "PENDING")
      refute StateMachine.allowed?("REJECTED", "PENDING")
      refute StateMachine.allowed?("NEEDS_HUMAN", "QUALIFIED")
    end

    test "unknown state returns false" do
      refute StateMachine.allowed?("MADE_UP", "PENDING")
      refute StateMachine.allowed?("PENDING", "MADE_UP")
    end
  end

  describe "terminal?/1" do
    test "true for HIRED, REJECTED, NEEDS_HUMAN" do
      assert StateMachine.terminal?("HIRED")
      assert StateMachine.terminal?("REJECTED")
      assert StateMachine.terminal?("NEEDS_HUMAN")
    end

    test "false for PENDING, QUALIFIED" do
      refute StateMachine.terminal?("PENDING")
      refute StateMachine.terminal?("QUALIFIED")
    end
  end

  describe "next/1" do
    test "PENDING has 4 next options (incl. self-loop)" do
      assert length(StateMachine.next("PENDING")) == 4
    end

    test "HIRED has no next" do
      assert StateMachine.next("HIRED") == []
    end
  end
end
```

### Step 2: Run failing + Step 3: Implement

Create `lib/showcase/recruit_flow/impl/state_machine.ex`:

```elixir
defmodule Showcase.RecruitFlow.Impl.StateMachine do
  @moduledoc """
  Pure 5-state machine for RecruitFlow Applications.

  States:
    * `PENDING` — initial; awaiting AI screen, or callback requested.
    * `QUALIFIED` — AI screen positive, awaiting CV.
    * `HIRED` — CV matched (terminal).
    * `REJECTED` — AI screen negative or stale (terminal).
    * `NEEDS_HUMAN` — AI uncertain (terminal).

  Transitions:
    * `PENDING` → `QUALIFIED | REJECTED | NEEDS_HUMAN | PENDING`
      (the self-loop handles callback outcomes — state stays but audit entry logged)
    * `QUALIFIED` → `HIRED | REJECTED`
    * Terminal states have no outgoing.
  """

  @transitions %{
    "PENDING" => ["PENDING", "QUALIFIED", "REJECTED", "NEEDS_HUMAN"],
    "QUALIFIED" => ["HIRED", "REJECTED"],
    "HIRED" => [],
    "REJECTED" => [],
    "NEEDS_HUMAN" => []
  }

  @states Map.keys(@transitions)

  @doc "All 5 states."
  @spec states() :: list(String.t())
  def states, do: @states

  @doc "Allowed next states from `state`. `[]` if state is unknown or terminal."
  @spec next(String.t()) :: list(String.t())
  def next(state), do: Map.get(@transitions, state, [])

  @doc "Is the transition `from → to` allowed?"
  @spec allowed?(String.t(), String.t()) :: boolean()
  def allowed?(from, to), do: to in next(from)

  @doc "Is `state` terminal (no outgoing transitions)?"
  @spec terminal?(String.t()) :: boolean()
  def terminal?(state), do: state in ~w(HIRED REJECTED NEEDS_HUMAN)
end
```

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/impl/state_machine_test.exs
git add lib/showcase/recruit_flow/impl/state_machine.ex test/showcase/recruit_flow/impl/state_machine_test.exs
git commit -m "feat(recruit_flow): StateMachine with 5 states + transition table"
```

Expected: ~13 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 3: `Transitions` boundary (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/transitions.ex`
- Create: `test/showcase/recruit_flow/transitions_test.exs`

**Contract:** `Transitions.apply/3` takes `(application_id, to_state, opts)` where `opts` carries `:actor`, `:reason`, optional `:transcript` / `:eval` attrs.
1. Load the Application.
2. Check `StateMachine.allowed?(app.state, to_state)`.
3. Update Application (state, state_changed_at, optionally transcript/eval) inside `Ecto.Multi`.
4. Write `Common.AuditLog` entry (outside Multi, post-tx).
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
        state: "PENDING",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app}}
  end

  test "apply/3 succeeds for an allowed transition", %{app: app} do
    Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")

    {:ok, updated} = Transitions.apply(app.id, "QUALIFIED", actor: "system", reason: "ai_qualified")
    assert updated.state == "QUALIFIED"
    assert_received {:recruit_flow, :transitioned, %{application_id: _, from: "PENDING", to: "QUALIFIED"}}
  end

  test "apply/3 supports the PENDING self-loop for callback outcomes", %{app: app} do
    {:ok, updated} = Transitions.apply(app.id, "PENDING", actor: "system", reason: "callback")
    assert updated.state == "PENDING"
  end

  test "apply/3 returns error for disallowed transition", %{app: app} do
    assert {:error, :invalid_transition} =
             Transitions.apply(app.id, "HIRED", actor: "system", reason: "skip")
  end

  test "apply/3 writes an AuditLog entry on success", %{app: app} do
    {:ok, _} = Transitions.apply(app.id, "QUALIFIED", actor: "system", reason: "ai_qualified")

    {:ok, audits} = Showcase.Common.AuditLog.for_entity("recruit_flow", "application", to_string(app.id))
    assert Enum.any?(audits, &(&1.event == "state_change"))
  end

  test "apply/3 updates eval/transcript when provided", %{app: app} do
    {:ok, app2} =
      Transitions.apply(app.id, "QUALIFIED",
        actor: "system",
        reason: "ai_qualified",
        transcript: "Hello!",
        eval: %{"outcome" => "qualified", "score" => 0.9, "reasoning" => "Good fit"}
      )

    assert app2.transcript == "Hello!"
    assert app2.eval["outcome"] == "qualified"
  end
end
```

### Step 2-3: Implement

Create `lib/showcase/recruit_flow/transitions.ex`:

```elixir
defmodule Showcase.RecruitFlow.Transitions do
  @moduledoc """
  Boundary that owns state transitions for RecruitFlow Applications.

  Every transition:
    1. Verifies StateMachine.allowed?(from, to).
    2. Updates Application (state + state_changed_at + optionally transcript/eval).
    3. Writes a Common.AuditLog entry with payload %{from, to, reason} (post-tx).
    4. Broadcasts {:recruit_flow, :transitioned, _} on the per-application topic.
  """

  alias Ecto.Multi
  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow.Impl.StateMachine
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.Repo

  @spec apply(integer(), String.t(), keyword()) ::
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

        app |> Application.changeset(attrs) |> Repo.update()
      end)

    case Repo.transaction(multi) do
      {:ok, %{load: app, update: updated}} ->
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

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/transitions_test.exs
git add lib/showcase/recruit_flow/transitions.ex test/showcase/recruit_flow/transitions_test.exs
git commit -m "feat(recruit_flow): Transitions boundary with AuditLog + PubSub"
```

Expected: 5 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 4: `MockPrompts` module

**Files:**
- Create: `lib/showcase/recruit_flow/mock_prompts.ex`

Same content as the earlier version: 4 phone scenarios (one per AI outcome) + 3 CV match scenarios.

```elixir
defmodule Showcase.RecruitFlow.MockPrompts do
  @moduledoc """
  Curated scenarios for RecruitFlow.

  * `phone_scenarios/0` — candidates with canned phone-screen responses (one
    per outcome: qualified / not_qualified / callback / needs_human).
  * `cv_match_scenarios/0` — CV bodies + expected matching info.

  Consumed by Seed + test setup via `RecruitFlow.register_mock_responses/0`.
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

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
git add lib/showcase/recruit_flow/mock_prompts.ex
git commit -m "feat(recruit_flow): MockPrompts with 4 phone + 3 CV scenarios"
```

## Report

Status, scenario counts, commit SHA.

---

## Task 5: `PhoneScreenPipeline` (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/phone_screen_pipeline.ex`
- Create: `test/showcase/recruit_flow/phone_screen_pipeline_test.exs`

**Contract:** `PhoneScreenPipeline.run/2` takes an Application + `%{now, scenario}`:
1. Call Claude with fingerprint `recruit_flow:phone_screen:v1`, scenario passed through.
2. Parse `{transcript, outcome, reasoning, score}`.
3. Map outcome → target state:
   - `qualified` → `QUALIFIED`
   - `not_qualified` → `REJECTED`
   - `needs_human` → `NEEDS_HUMAN`
   - `callback` → `PENDING` (self-loop — audit entry records the callback request)
4. Call `Transitions.apply(app.id, target_state, ...)` with the eval + transcript.

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
    {:ok, c} = %Candidate{} |> Candidate.changeset(candidate_attrs) |> Repo.insert()

    {:ok, app} =
      %Application{}
      |> Application.changeset(%{
        candidate_id: c.id,
        position_id: position.id,
        state: "PENDING",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    app
  end

  defp ctx_with(scenario), do: %{now: DateTime.utc_now(), scenario: scenario}

  test "qualified outcome → QUALIFIED", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "alice_qualified"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "QUALIFIED"
    assert updated.eval["outcome"] == "qualified"
    assert is_binary(updated.transcript)
  end

  test "not_qualified outcome → REJECTED", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "bob_not_qualified"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "REJECTED"
  end

  test "needs_human outcome → NEEDS_HUMAN", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "dan_needs_human"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "NEEDS_HUMAN"
  end

  test "callback outcome stays in PENDING (with audit entry)", %{position: position} do
    s = Enum.find(MockPrompts.phone_scenarios(), &(&1.name == "carol_callback"))
    app = insert_app(position, s.candidate)
    Mock.register("recruit_flow:phone_screen:v1", scenario: s.name, text: s.claude_response)

    {:ok, updated} = PhoneScreenPipeline.run(app, ctx_with(s.name))
    assert updated.state == "PENDING"

    {:ok, audits} = Showcase.Common.AuditLog.for_entity("recruit_flow", "application", to_string(app.id))
    assert Enum.any?(audits, fn a -> a.event == "state_change" and a.payload["reason"] =~ "callback" end)
  end
end
```

### Step 2-3: Implement

Create `lib/showcase/recruit_flow/phone_screen_pipeline.ex`:

```elixir
defmodule Showcase.RecruitFlow.PhoneScreenPipeline do
  @moduledoc """
  Boundary that runs a phone screen for an Application.

  Flow: Claude call → parse → map outcome → Transitions.apply.

  outcome → target state:
    * "qualified"     → QUALIFIED
    * "not_qualified" → REJECTED
    * "needs_human"   → NEEDS_HUMAN
    * "callback"      → PENDING (self-loop; audit entry notes the callback)
  """

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions

  @fingerprint "recruit_flow:phone_screen:v1"
  @model "claude-haiku-4-5-20251001"
  @system_prompt """
  You are simulating a phone screen. Generate a brief transcript (3-6 exchanges)
  and score the candidate.

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
    "not_qualified" => "REJECTED",
    "needs_human" => "NEEDS_HUMAN",
    "callback" => "PENDING"
  }

  def run(%Application{} = app, %{now: _now, scenario: scenario}) do
    req = %Request{
      model: @model,
      messages: [%{role: "user", content: "Run a phone screen."}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, parsed, _completeness} <- ResilientJSONParser.parse(response.text),
         {:ok, target} <- target_state(parsed["outcome"]),
         {:ok, updated} <-
           Transitions.apply(app.id, target,
             actor: "system",
             reason: "ai_screen:#{parsed["outcome"]}",
             transcript: parsed["transcript"],
             eval: parsed
           ) do
      {:ok, updated}
    end
  end

  defp target_state(outcome) do
    case Map.get(@outcome_to_state, outcome) do
      nil -> {:error, {:unknown_outcome, outcome}}
      state -> {:ok, state}
    end
  end
end
```

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/phone_screen_pipeline_test.exs
git add lib/showcase/recruit_flow/phone_screen_pipeline.ex test/showcase/recruit_flow/phone_screen_pipeline_test.exs
git commit -m "feat(recruit_flow): PhoneScreenPipeline with 4-outcome routing"
```

Expected: 4 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 6: 5-priority CV cascade step modules (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/cascade/{exact_email,exact_phone,subject_line,fuzzy_name,pdf_content}_step.ex`
- Create: `test/showcase/recruit_flow/cascade_test.exs`

**Same as before** — 5 step modules each implementing `Showcase.Common.CascadeMatcher.Step`. The "awaiting CV" predicate now checks `state == "QUALIFIED"` (single state, no more `state in [AWAITING_CV, CV_FOLLOWUP_SENT]`).

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
        state: "QUALIFIED",
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

### Step 2-3: Implement all 5 step modules

Create `lib/showcase/recruit_flow/cascade/exact_email_step.ex`:

```elixir
defmodule Showcase.RecruitFlow.Cascade.ExactEmailStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @impl true
  def name, do: :exact_email

  @impl true
  def try_match(%{email: email}, %{repo: repo}) when is_binary(email) and email != "" do
    case repo.one(
           from a in Application,
             join: c in Candidate, on: c.id == a.candidate_id,
             where: c.email == ^email and a.state == "QUALIFIED",
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

  @impl true
  def name, do: :exact_phone

  @impl true
  def try_match(%{phone: phone}, %{repo: repo}) when is_binary(phone) and phone != "" do
    case repo.one(
           from a in Application,
             join: c in Candidate, on: c.id == a.candidate_id,
             where: c.phone == ^phone and a.state == "QUALIFIED",
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

  @impl true
  def name, do: :subject_line

  @impl true
  def try_match(%{subject_line: subj}, %{repo: repo}) when is_binary(subj) and subj != "" do
    case Regex.run(~r/Application #C-(\d+)/i, subj) do
      [_, id_string] ->
        with {id, ""} <- Integer.parse(id_string),
             %Application{state: "QUALIFIED"} = app <- repo.get(Application, id) do
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

  @similarity_threshold 0.6

  @impl true
  def name, do: :fuzzy_name

  @impl true
  def try_match(%{pdf_text: pdf}, %{repo: repo}) when is_binary(pdf) and pdf != "" do
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
            where: a.state == "QUALIFIED",
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
               where: c.name == ^name and a.state == "QUALIFIED",
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

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/cascade_test.exs
git add lib/showcase/recruit_flow/cascade/ test/showcase/recruit_flow/cascade_test.exs
git commit -m "feat(recruit_flow): 5-priority CV cascade steps"
```

Expected: 9 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 7: `CvMatcher` boundary (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/cv_matcher.ex`
- Create: `test/showcase/recruit_flow/cv_matcher_test.exs`

**Contract:** `CvMatcher.process_cv/2` takes a `%{email, phone, subject_line, pdf_text}` payload + `%{now}`:
1. Run `CascadeMatcher.run/3` with 5 steps.
2. If matched: insert a CV row + transition Application QUALIFIED → HIRED.
3. If no match: return `{:no_match, outcome}` (no DB writes).

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
        state: "QUALIFIED",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, %{app: app, candidate: candidate}}
  end

  test "process_cv with matching email → Application transitions to HIRED", %{app: app} do
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
    assert updated_app.state == "HIRED"
  end

  test "process_cv with no match → returns :no_match" do
    payload = %{
      email: "ghost@nowhere.com",
      phone: nil,
      subject_line: nil,
      pdf_text: "Random PDF nothing matches"
    }

    {:no_match, outcome} = CvMatcher.process_cv(payload, %{now: DateTime.utc_now()})
    refute outcome.matched
  end
end
```

### Step 2-3: Implement

Create `lib/showcase/recruit_flow/cv_matcher.ex`:

```elixir
defmodule Showcase.RecruitFlow.CvMatcher do
  @moduledoc """
  Boundary that runs the 5-priority CV cascade and transitions the matched
  Application from QUALIFIED → HIRED.
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

      {:ok, _} =
        Transitions.apply(outcome.value, "HIRED",
          actor: "system",
          reason: "cv_matched:#{outcome.step}"
        )

      {:ok, cv, outcome}
    else
      {:no_match, outcome}
    end
  end
end
```

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/cv_matcher_test.exs
git add lib/showcase/recruit_flow/cv_matcher.ex test/showcase/recruit_flow/cv_matcher_test.exs
git commit -m "feat(recruit_flow): CvMatcher boundary — cascade + QUALIFIED → HIRED"
```

Expected: 2 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 8: `Scheduler` with one tick (TDD)

**Files:**
- Create: `lib/showcase/recruit_flow/scheduler.ex`
- Create: `test/showcase/recruit_flow/scheduler_test.exs`

**Contract:** Single tick: `Scheduler.auto_close_stale_qualified/1` takes `%{now}` and transitions QUALIFIED applications older than 7 days to REJECTED with reason `"stale_no_cv"`. Returns count of advanced applications.

`Scheduler.tick_all/1` returns a summary map with one entry.

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

  defp insert_app(position, state, ts) do
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

  test "auto_close_stale_qualified only touches QUALIFIED older than 7 days", %{position: position} do
    now = DateTime.utc_now()
    fresh = insert_app(position, "QUALIFIED", DateTime.add(now, -3, :day))
    stale = insert_app(position, "QUALIFIED", DateTime.add(now, -10, :day))
    rejected = insert_app(position, "REJECTED", DateTime.add(now, -10, :day))

    count = Scheduler.auto_close_stale_qualified(%{now: now})
    assert count == 1

    assert Repo.get!(Application, fresh.id).state == "QUALIFIED"
    assert Repo.get!(Application, stale.id).state == "REJECTED"
    assert Repo.get!(Application, rejected.id).state == "REJECTED"
  end

  test "tick_all returns a summary map", %{position: position} do
    insert_app(position, "QUALIFIED", DateTime.add(DateTime.utc_now(), -10, :day))

    summary = Scheduler.tick_all(%{now: DateTime.utc_now()})
    assert is_map(summary)
    assert Map.has_key?(summary, :auto_close_stale_qualified)
  end
end
```

### Step 2-3: Implement

Create `lib/showcase/recruit_flow/scheduler.ex`:

```elixir
defmodule Showcase.RecruitFlow.Scheduler do
  @moduledoc """
  RecruitFlow scheduler. One visible tick — `auto_close_stale_qualified` —
  demonstrates the AE-driven scheduler pattern without bloat.

  `tick_all/1` exists for UI symmetry; expand it as future ticks are added.
  """

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.RecruitFlow.Transitions
  alias Showcase.Repo

  @stale_qualified_age_days 7

  def auto_close_stale_qualified(%{now: now}) do
    threshold = DateTime.add(now, -@stale_qualified_age_days, :day)

    ids =
      Repo.all(
        from a in Application,
          where: a.state == "QUALIFIED" and a.state_changed_at <= ^threshold,
          select: a.id
      )

    Enum.reduce(ids, 0, fn id, acc ->
      case Transitions.apply(id, "REJECTED", actor: "system", reason: "stale_no_cv") do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  def tick_all(%{now: _now} = ctx) do
    %{auto_close_stale_qualified: auto_close_stale_qualified(ctx)}
  end
end
```

### Step 4: Run + commit

```bash
mix test test/showcase/recruit_flow/scheduler_test.exs
git add lib/showcase/recruit_flow/scheduler.ex test/showcase/recruit_flow/scheduler_test.exs
git commit -m "feat(recruit_flow): Scheduler with single auto_close_stale_qualified tick"
```

Expected: 2 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 9: `RecruitFlow` public context + `Seed` (TDD on Seed)

**Files:**
- Create: `lib/showcase/recruit_flow.ex`
- Create: `lib/showcase/recruit_flow/seed.ex`
- Create: `test/showcase/recruit_flow/seed_test.exs`

### Implementation

Create `lib/showcase/recruit_flow.ex`:

```elixir
defmodule Showcase.RecruitFlow do
  @moduledoc "Public context for RecruitFlow."

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

    Enum.each(MockPrompts.cv_match_scenarios(), fn s ->
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
  @moduledoc "Seeds RecruitFlow with positions, candidates, applications."

  @behaviour Showcase.Common.DemoSeeder

  alias Showcase.RecruitFlow.MockPrompts
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate, Position}
  alias Showcase.Repo

  @impl true
  def name, do: "RecruitFlow"

  @impl true
  def description do
    "Phone-screen, score, and chase candidates through a 5-state funnel. Recruiters intervene only on the ambiguous middle."
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
            default_prompt_body: "You are screening for a Software Engineer role at Neurony."
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
            state: "PENDING",
            state_changed_at: DateTime.utc_now()
          })
          |> Repo.insert!()

        _ -> :noop
      end
    end)
  end
end
```

```bash
mix test test/showcase/recruit_flow/seed_test.exs
git add lib/showcase/recruit_flow.ex lib/showcase/recruit_flow/seed.ex test/showcase/recruit_flow/seed_test.exs
git commit -m "feat(recruit_flow): public context + Seed with DemoSeeder behaviour"
```

Expected: 4 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 10: `KanbanLive` at `/recruit-flow` (TDD)

**Files:**
- Create: `lib/showcase_web/live/recruit_flow/kanban_live.ex`
- Create: `test/showcase_web/live/recruit_flow/kanban_live_test.exs`
- Modify: `lib/showcase_web/router.ex`

**Contract:** 5 columns (one per state). Per PENDING card: "Run AI screen" with 4 scenario buttons (alice/bob/carol/dan). Per QUALIFIED card: "CV arrived" buttons for each CV scenario. "Tick scheduler" button at top.

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

  test "renders the 5-column board", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/recruit-flow")

    assert html =~ "RecruitFlow"
    assert html =~ "PENDING"
    assert html =~ "QUALIFIED"
    assert html =~ "HIRED"
    assert html =~ "REJECTED"
    assert html =~ "NEEDS_HUMAN"
    assert html =~ "Alice Anderson"
  end

  test "running AI screen transitions an application", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/recruit-flow")

    # Find the first PENDING application and trigger its AI screen with "alice_qualified"
    render_click(view, "run_ai_screen", %{"id" => first_pending_id(view), "scenario" => "alice_qualified"})

    html = render(view)
    assert html =~ "QUALIFIED"
  end

  defp first_pending_id(view) do
    # The Kanban includes phx-value-id on each Run buttons; use a simple LiveView assigns lookup.
    # Tests rely on the seeded ordering.
    apps = Showcase.RecruitFlow.applications_by_state()
    pending = Map.get(apps, "PENDING", [])
    hd(pending).id
  end
end
```

### Step 2: Add routes

In `lib/showcase_web/router.ex`, public scope:

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
  alias Showcase.RecruitFlow.{CvMatcher, MockPrompts, PhoneScreenPipeline, Scheduler}

  @columns ~w(PENDING QUALIFIED HIRED REJECTED NEEDS_HUMAN)

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
     |> assign(:columns, @columns)
     |> assign(:by_state, RecruitFlow.applications_by_state())
     |> assign(:phone_scenarios, MockPrompts.phone_scenarios())
     |> assign(:cv_scenarios, MockPrompts.cv_match_scenarios())
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

  def handle_event("cv_arrived", %{"scenario" => scenario_name}, socket) do
    scenario =
      Enum.find(socket.assigns.cv_scenarios, &(&1.name == scenario_name))

    payload = %{
      email: scenario.candidate_email,
      phone: scenario.candidate_phone,
      subject_line: scenario.subject_line,
      pdf_text: scenario.pdf_text
    }

    case CvMatcher.process_cv(payload, %{now: DateTime.utc_now()}) do
      {:ok, _cv, outcome} ->
        {:noreply,
         socket
         |> assign(:by_state, RecruitFlow.applications_by_state())
         |> put_flash(:info, "CV matched via #{outcome.step}.")}

      {:no_match, _} ->
        {:noreply, put_flash(socket, :info, "CV processed; no Application matched.")}
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
              5-state recruitment funnel with AI phone screens + CV cascade.
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

      <main class="max-w-7xl mx-auto px-6 py-6">
        <div class="grid grid-cols-5 gap-3">
          <section :for={state <- @columns} class="rounded border bg-white p-3">
            <h2 class="text-xs uppercase tracking-wide text-zinc-500 mb-2">{state}</h2>
            <ul class="space-y-2">
              <li :for={app <- Map.get(@by_state, state, [])} class="rounded border bg-zinc-50 p-2 text-xs">
                <a href={"/recruit-flow/applications/#{app.id}"} class="font-medium hover:underline">
                  {app.candidate.name}
                </a>
                <p class="text-zinc-500 mt-0.5">{app.position && app.position.title}</p>
                <%= if state == "PENDING" do %>
                  <div class="mt-2 flex flex-col gap-1">
                    <button
                      :for={s <- @phone_scenarios}
                      type="button"
                      class="text-[10px] underline text-emerald-700 text-left"
                      phx-click="run_ai_screen"
                      phx-value-id={app.id}
                      phx-value-scenario={s.name}
                    >
                      Run as: {s.name}
                    </button>
                  </div>
                <% end %>
              </li>
            </ul>

            <%= if state == "QUALIFIED" and Map.get(@by_state, "QUALIFIED", []) != [] do %>
              <div class="mt-3 pt-3 border-t border-zinc-200">
                <p class="text-[10px] uppercase tracking-wide text-zinc-400 mb-1">CV arrived:</p>
                <div class="flex flex-col gap-1">
                  <button
                    :for={cv <- @cv_scenarios}
                    type="button"
                    class="text-[10px] underline text-emerald-700 text-left"
                    phx-click="cv_arrived"
                    phx-value-scenario={cv.name}
                  >
                    {cv.name}
                  </button>
                </div>
              </div>
            <% end %>
          </section>
        </div>
      </main>
    </div>
    """
  end
end
```

### Step 4-5: Run + commit

```bash
mix test test/showcase_web/live/recruit_flow/kanban_live_test.exs 2>&1 | tail -5
git add lib/showcase_web/live/recruit_flow/kanban_live.ex test/showcase_web/live/recruit_flow/kanban_live_test.exs lib/showcase_web/router.ex
git commit -m "feat(web): RecruitFlow KanbanLive with 5-column board"
```

Expected: 2 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 11: `ApplicationDetailLive` (TDD)

**Files:**
- Create: `lib/showcase_web/live/recruit_flow/application_detail_live.ex`
- Create: `test/showcase_web/live/recruit_flow/application_detail_live_test.exs`

**Contract:** Shows one Application's transcript, eval, AuditLog timeline, and per-scenario AI screen / CV arrived buttons. Subscribes to PubSub for live updates.

### Step 1: Failing tests

Create `test/showcase_web/live/recruit_flow/application_detail_live_test.exs`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

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

  test "renders the detail page", %{conn: conn, app: app} do
    {:ok, _view, html} = live(conn, "/recruit-flow/applications/#{app.id}")

    assert html =~ app.candidate.name
    assert html =~ "PENDING"
  end

  test "running AI screen transitions the application", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    updated = Repo.get!(Application, app.id)
    refute updated.state == "PENDING"
  end

  test "transition timeline shows audit log entries", %{conn: conn, app: app} do
    {:ok, view, _html} = live(conn, "/recruit-flow/applications/#{app.id}")

    render_click(view, "run_ai_screen", %{"scenario" => "alice_qualified"})

    html = render(view)
    assert html =~ "state_change"
  end
end
```

### Step 2-3: Implement

Create `lib/showcase_web/live/recruit_flow/application_detail_live.ex`:

```elixir
defmodule ShowcaseWeb.RecruitFlow.ApplicationDetailLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow
  alias Showcase.RecruitFlow.{MockPrompts, PhoneScreenPipeline}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    app = RecruitFlow.find_application(String.to_integer(id))

    if app == nil do
      {:ok, push_navigate(socket, to: "/recruit-flow")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Showcase.PubSub, "recruit_flow:applications:#{app.id}")
      end

      {:ok, socket |> assign_app(app) |> assign(:phone_scenarios, MockPrompts.phone_scenarios())}
    end
  end

  defp assign_app(socket, app) do
    {:ok, audits} = AuditLog.for_entity("recruit_flow", "application", to_string(app.id))

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
    {:noreply, assign_app(socket, RecruitFlow.find_application(id))}
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
                :for={s <- @phone_scenarios}
                type="button"
                class="text-xs underline text-emerald-700 text-left"
                phx-click="run_ai_screen"
                phx-value-scenario={s.name}
              >
                {s.name}
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
                  <p class="text-zinc-500">{entry.payload["from"]} → {entry.payload["to"]}</p>
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

### Step 4: Run + commit

```bash
mix test test/showcase_web/live/recruit_flow/application_detail_live_test.exs
git add lib/showcase_web/live/recruit_flow/application_detail_live.ex test/showcase_web/live/recruit_flow/application_detail_live_test.exs
git commit -m "feat(web): RecruitFlow ApplicationDetailLive with transcript + audit timeline"
```

Expected: 3 tests, 0 failures.

## Report

Status, test count, commit SHA.

---

## Task 12: TileConfig flip + smoke test + phase-4 tag

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
        "Phone-screen, score, and chase candidates through a 5-state recruitment funnel with AI screens + CV cascade.",
      roi_hook: "Recruiters intervene only on the ambiguous middle — everything else moves automatically.",
      status: :live,
      path: "/recruit-flow",
      seeder: Showcase.RecruitFlow.Seed
    },
```

### Step 2: Update tile_config_test.exs

Replace the test `"OrderFlow and Invoice Approval are live"` with:

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

Remove any earlier "are coming_soon" test that included `:recruit_flow`.

### Step 3-7: Run + smoke + tag + commit

```bash
mix test 2>&1 | tail -3
mix compile --warnings-as-errors 2>&1 | tail -3
curl -s -o /dev/null -w "GET / → %{http_code}\n" http://localhost:4321/
curl -s -o /dev/null -w "GET /recruit-flow → %{http_code}\n" http://localhost:4321/recruit-flow
curl -s -o /dev/null -w "GET /admin/reset auth → %{http_code}\n" -u admin:changeme http://localhost:4321/admin/reset

git add lib/showcase/dashboard/tile_config.ex test/showcase/dashboard/tile_config_test.exs
git commit -m "feat(dashboard): flip RecruitFlow tile from coming_soon to live"

git tag -a phase-4 -m "Phase 4 RecruitFlow complete: 5-state machine, AI phone screen, 5-priority CV cascade"
git tag -l 'phase-*'
```

Expected: all 200, ~200 tests, tags phase-0..phase-4.

## Report

Status, test count, route responses, tag confirmation.

---

## Phase 4 acceptance criteria

- [ ] `mix test` green; ~200 tests pass
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `GET /recruit-flow` renders 5-column board (PENDING / QUALIFIED / HIRED / REJECTED / NEEDS_HUMAN)
- [ ] `GET /recruit-flow/applications/:id` renders transcript + eval + audit timeline
- [ ] "Run AI screen" with each of 4 scenarios drives Application to QUALIFIED / REJECTED / NEEDS_HUMAN / (PENDING for callback)
- [ ] "CV arrived" + matching scenario transitions QUALIFIED → HIRED
- [ ] AuditLog records every state transition (including PENDING self-loops for callback)
- [ ] Dashboard `/` shows RecruitFlow as `:live`
- [ ] `/admin/reset` has a "Reset RecruitFlow" button
- [ ] `phase-4` tag in git history

Next plan (Phase 5: Planogram) — vision call + role switcher + cost transparency + mobile QR handoff.
