# Neurony AI Showcase — Design

**Date:** 2026-06-04
**Status:** Approved (pending written review)
**Owner:** Alexandru Rădulescu

---

## 1. Goal

Build a polished, AE-driven sales demo that walks a prospect through five real AI-mediated workflows Neurony has built. The app sells *Neurony's AI integration capability* — the demos are the evidence. Five demos sit behind a dashboard:

1. **OrderFlow** — turns unstructured customer messages into structured orders
2. **RecruitFlow** — top-of-funnel recruitment automation with AI phone screens + state-machine-driven funnel
3. **Planogram Manager** — retail shelf compliance via vision
4. **Invoice Approval** — three-way contract / delivery-note / invoice match with explainable verdicts
5. **Restaurant Compliance Validation** — deferred; brief pending

Success criteria: an AE can run the dashboard cold in front of a prospect, click through any demo in any order, hit reset between meetings, and have the demos do what they promise — execute the real AI pipeline (against synthetic input), surface the engineering choices that make them work, and land each demo's value claim in under five minutes.

## 2. Confirmed decisions

| Decision | Choice | Notes |
|---|---|---|
| Tech stack | Elixir / Phoenix / LiveView | User's standing default for new apps |
| App framework | Ash where it earns its keep, plain Ecto elsewhere | See §3 for the split |
| Background work | Oban free | Per-demo queues; cron jobs for RecruitFlow's 5-tick scheduler |
| Database | PostgreSQL | Required by Oban; also needed for `pg_trgm` fuzzy matching |
| Operator mode | Sales demo, AE-driven, in front of prospect | Drives every UX trade-off |
| Language | English only | No i18n machinery |
| Dashboard | Launcher with value framing | 5 tiles, each with one-line value statement + ROI hook |
| Visual design | Follow Neurony brand | Assets needed at polish phase (§9) |
| State / reset | Single shared instance + reset button | One URL, admin clicks "Reset" between meetings |
| Form factor | Desktop primary, Planogram mobile beat | QR-code handoff for the capture moment |
| Codebase structure | Single Phoenix app, namespaced contexts | Right scale for 5 demos always shipped together |

## 3. Architecture

### 3.1 Layout

Single Mix project, single Phoenix app, single OTP application called `:showcase`:

```
lib/
  showcase/                          # business contexts — no Phoenix concerns
    common/                          # shared infrastructure
      system_prompt.ex               # Ash resource: live-editable prompts, scoped by demo
      cascade_matcher.ex             # generic exact → fuzzy → llm-fallback engine
      resilient_json_parser.ex       # salvages truncated LLM responses
      needs_human.ex                 # contract every demo implements for escalation
      audit_log.ex                   # append-only Ash resource
      demo_seeder.ex                 # idempotent per-demo seed + one-shot reset
      anthropic_client.ex            # thin API wrapper + token-usage telemetry
    order_flow/
      impl/                          # pure functions
      pipeline.ex                    # boundary: orchestrates Oban-driven steps
      schemas/                       # Client, Product, Order, ProductAlias, ...
      seed.ex
    recruit_flow/                    # same shape
    planogram/
    invoice_approval/
    restaurant_compliance/           # placeholder, deferred
    dashboard/                       # tile config, value copy, reset orchestration
  showcase_web/
    live/
      dashboard_live.ex
      order_flow/                    # per-demo LiveViews + components
      recruit_flow/
      planogram/
        merchandiser_live.ex
        manager_live.ex
        mobile_live.ex               # QR-handoff capture surface
      invoice_approval/
      admin/
        system_prompts_live.ex
        reset_live.ex
        audit_log_live.ex
    components/                      # shared UI primitives
```

### 3.2 Three load-bearing boundaries

1. **`impl/` vs boundaries.** Pure functions in every demo's `impl/` directory — no `Repo`, no HTTP, no IO, no clock reads (`DateTime.utc_now/0`, `Date.utc_today/0`). Boundaries (each demo's `pipeline.ex`) own `Ecto.Multi`, transactions, Oban enqueues, side effects, and supply the "current time" as an argument when `impl/` needs it. Enforced by code review, not tooling, but it is the single most load-bearing rule. Tests for `impl/` are unit tests; tests for boundaries are integration tests against `AnthropicClient.Mock`.
2. **`Common` is depended-on, never depends up.** It knows nothing about any specific demo. Demos depend on `Common`. Building the cascade matcher, JSON parser, prompt admin, audit log, and reset machinery *once* is what makes cross-demo consistency real — the `NeedsHumanBadge` looks identical across all four live demos because it lives in `Common`.
3. **`Dashboard` orchestrates demos but doesn't own their data.** It reads each demo's seeder module to render value-framed tiles and calls each demo's reset function during global reset. Demos do not reach back into `Dashboard`. One-way dependency.

### 3.3 Database

One Postgres instance, one database, one schema. Tables are prefixed per demo:

- `common_*` — shared infrastructure (system_prompts, audit_log, ...)
- `of_*` — OrderFlow (clients, products, orders, product_aliases, ...)
- `rf_*` — RecruitFlow (candidates, positions, applications, transitions, ...)
- `pg_*` — Planogram (stores, planograms, verification_tasks, ...)
- `ia_*` — Invoice Approval (contracts, invoices, delivery_notes, ...)
- `rc_*` — Restaurant Compliance (placeholder)

Cross-demo joins are forbidden by convention. Each demo's surface area is its own tables + `Common`. Reset is per-demo: `TRUNCATE` the tables sharing that prefix (enumerated explicitly per demo, since Postgres `TRUNCATE` does not pattern-match table names) inside a transaction, then re-seed from the demo's `seed.ex`.

The `pg_trgm` extension is enabled at migration time; `CascadeMatcher`'s fuzzy step depends on it.

### 3.4 Oban

Free version. One queue per demo: `:order_flow`, `:recruit_flow`, `:planogram`, `:invoice_approval`. Per-queue isolation makes pipeline progress visible in the Oban dashboard during demos — a quiet but useful AE talking point. (Specific dashboard package — Oban Web vs Phoenix LiveDashboard's Oban integration — chosen at phase 0.)

RecruitFlow's five scheduler ticks (call submission, stuck-call polling, CV inbox polling, follow-ups, stale-rejection close) are Oban cron jobs. They tick on their natural cadences in normal use; the `Tick scheduler` demo button manually inserts one of each.

### 3.5 Ash — cherry-picked usage

| Use Ash for | Use plain Ecto + LiveView for |
|---|---|
| `SystemPrompt` (admin generated for free) | Per-demo pipeline orchestration |
| `AuditLog` (declarative, queryable) | LiveView assigns, PubSub-driven UI |
| Demo entities: `Client`, `Product`, `Application`, `Invoice`, `Contract`, etc. — where the DSL gives validation + policies cheaply | The reset machinery |
| Per-Position prompt versioning (RecruitFlow) | The cascade matcher (it's algorithmic, not data-modeled) |

Ash 3.x. Where the Ash DSL versus Ecto's lower-level API is genuinely ambiguous, lean toward Ecto for anything inside a `Pipeline` boundary — pipelines need to read clearly to an Elixir developer who's never seen Ash. Resources and admin surfaces are where Ash shines.

### 3.6 Anthropic client

Thin wrapper around an Elixir Anthropic SDK (specific library chosen at phase 0 — e.g., `:anthropix` or a hand-rolled `Req`-backed client if no SDK fits):

- Returns `{:ok, %{response, usage, cost_estimate}}` or `{:error, reason}`
- Surfaces token usage per call — load-bearing for the Planogram cost-transparency UI
- Configurable timeout per call
- Telemetry events emitted on every call (model, tokens in/out, latency, cost)
- A `Mock` implementation lives in `test/` for boundary tests — keyed by prompt fingerprint + scenario name

### 3.7 Auth model

- **Demo surfaces** are open. Anyone with the URL drives them.
- **Admin surfaces** (system prompts, reset, audit log, LiveDashboard, Oban dashboard) sit behind a single AE credential (basic-auth or `Plug.Session` with one configured user). Credentials live in env vars, not in DB.
- Prospect-facing screens never expose admin links.

### 3.8 Planogram mobile handoff

The capture step on the Merchandiser view renders a QR code encoding `/planogram/mobile/{task_token}`. The token is single-use and scoped to one verification task. Scanning opens the mobile capture surface in the visitor's browser; photo upload via `Phoenix.LiveView.Upload` propagates back to the desktop view via PubSub. No separate auth — the task token is the credential.

If the AE prefers not to use a phone, the desktop "Capture" button also opens a bundled photo picker.

## 4. Per-demo design briefs

Each demo's full implementation-time design will refine these — but every brief below is locked in for the architecture spec.

### 4.1 OrderFlow

**Headline value claim:** Turn unstructured customer messages into clean structured orders without manual re-keying — and have the system get smarter every time a human corrects it.

**Surface:** Split LiveView. Left pane is a synthetic inbox of pending messages (emails + WhatsApp + the occasional handwritten photo). Right pane is the live pipeline visualizer that lights up stage-by-stage as a message is processed.

**Controls:** `Generate order` (creates a synthetic message from the seeded bundle), `Reset OrderFlow`.

**Pipeline (Oban `:order_flow`):** `extract → identify_client → cascade-match each line → create Order`. Each stage PubSubs progress; the LiveView animates accordingly.

**The cascade — five steps per line item:** exact text match → fuzzy trigram match → client-scoped `ProductAlias` → global `ProductAlias` → Claude fallback. Each step has a confidence score; the visualization makes the matching path visible.

**Self-improving loop:** Corrections in the order-review UI write `ProductAlias` rows scoped to the client. Confidence +0.05 per re-use, decay at 6 / 12 months. Promotion from client-scoped to global once ≥2 distinct clients confirm the same mapping. Re-running the same message after a correction skips the LLM for that line — that is the visible payoff and must be demonstrated.

**`Common` components used:** `SystemPrompt` (extraction + matching prompts, live-editable), `CascadeMatcher`, `ResilientJSONParser`, `NeedsHuman` (low-confidence flagging), `AnthropicClient`.

**Developer toggle:** "Show cascade detail" — surfaces which step matched each line at what confidence. Off by default in prospect view; AE flips on when asked "how does it work?"

### 4.2 RecruitFlow

**Headline value claim:** Phone-screen, score, and chase candidates through a complete recruitment funnel without anyone re-keying status updates. Humans only intervene where the AI is genuinely uncertain.

**Surface:** Kanban of Applications across the 18 states. Side panel shows the active Position's prompt template + the recent transitions audit log.

**Controls:** `New candidate` (roster + open position → Application in `PENDING_CALL`), `Run AI screen` (Claude plays the candidate against the Position prompt, generates a transcript, eval returns one of `qualified | not_qualified | callback | needs_human`, state advances), `CV arrived` (pick a bundled PDF, runs the 5-priority CV cascade), `Tick scheduler` (advances all five Oban cron jobs once on demand), `Edit prompt` (versioned template editor with placeholders).

**Pipeline (Oban `:recruit_flow`):** All state transitions live in `RecruitFlow.Transitions` — single source of truth, no scattered status mutations. Every transition writes to `Common.AuditLog`.

**The five background jobs** (visible in the UI with cadences shown): submit queued calls, poll stuck calls, poll CV inbox, send CV follow-ups, auto-close stale rejections.

**The 5-priority CV cascade:** exact email → phone → subject-line ID → fuzzy name → PDF content. Low-confidence matches get flagged `needs_review`. The cascade UI uses the *same* `CascadeMatrix` component as OrderFlow — that visual repetition is intentional and is the cross-demo teaching point.

**`Common` components used:** `SystemPrompt` (versioned per Position), `CascadeMatcher`, `NeedsHuman`, `AuditLog`, `AnthropicClient`.

### 4.3 Planogram Manager

**Headline value claim:** Retail compliance audits done in 15 seconds instead of an afternoon. One vision call returns score, per-row breakdown, issues, suggestions, and a product extraction — and the system shows its receipts.

**Surface:** Role switcher in the chrome (Admin / Manager / Merchandiser). Main work in Merchandiser view — tasks grouped Today / Tomorrow / Overdue (red).

**Controls:** `Switch role`, `Upload planogram` (Manager, bundled reference set), `Create task` (Manager — past dates allowed, for demonstrating overdue treatment), `Capture photo` (Merchandiser — bundled photo set OR `Open on phone` QR button), `Run analysis` (real Claude vision), `Force truncation` (hidden dev toggle that caps `max_tokens` to demo the parser).

**Pipeline (Oban `:planogram`):** Single rich-JSON Claude vision call → `ResilientJSONParser` → render full results: compliance gauge, executive summary, per-row breakdown with status, issues with type + severity + business impact, unauthorized items, suggestions, photo-quality assessment, extracted products list. LiveView streams the assigned result via PubSub on completion.

**Date-driven overdue (kept):** No cron mutates statuses. Overdue is a query-time computed field. This is worth explicitly pointing at on screen.

**`Common` components used:** `SystemPrompt` (active prompt, model selection, token budget), `ResilientJSONParser`, `NeedsHuman` (photo-quality flagging), `AnthropicClient`, `CostBadge`.

**Developer panel:** Raw JSON inspector + cost/token counter visible on every result.

### 4.4 Invoice Approval

**Headline value claim:** Three-way document matching with explainable verdicts. The AI doesn't replace the AP clerk — it scopes their work to the genuinely ambiguous middle and shows them why.

**Surface:** Left: queue of pending invoices. Middle: 3-way match view — **Contract / Delivery Note / Invoice** columns aligned by line item, discrepancies color-coded (green / amber / red). Right: tolerance sliders + reasoning + audit log.

**Controls:** `Pick client` (seeded clients, each with attached contract), `Drop documents` (curated scenarios: clean match / qty mismatch / price drift / expired contract / out-of-contract product / missing delivery note / wrong currency / ...), `Run approval`, `Edit thresholds` (price %, qty %, date days — re-runs the same documents live), `Override verdict` (writes audit + feedback signal).

**Pipeline (Oban `:invoice_approval`):** Multi-document Claude call (1 contract + N delivery notes + 1 invoice in a single request) → `ResilientJSONParser` → `%Verdict{outcome, reasoning, matching_matrix}` where `outcome ∈ {:approve, :reject, :needs_human}`.

**The verdict-ratio panel:** A small live dashboard showing how the same scenario set redistributes across approve / reject / needs_human as thresholds change. This is the lesson: AI scopes humans to ambiguous cases; configuration is the dial.

**`Common` components used:** `SystemPrompt`, `ResilientJSONParser`, `NeedsHuman`, `AuditLog`, `AnthropicClient`.

### 4.5 Restaurant Compliance Validation — deferred

Slot reserved: `lib/showcase/restaurant_compliance/` exists with skeleton + seed module. Dashboard tile renders "Coming soon" or hides behind a feature flag.

**Working hypothesis** (revisit when brief lands): vision call with reference images + actual restaurant images + a rules document → checklist-style compliance report. Likely reuses `ResilientJSONParser`, `SystemPrompt`, `NeedsHuman`, `AnthropicClient`.

## 5. Shared LiveView components

In `showcase_web/components/`. Every demo uses the same versions.

| Component | Used by | Purpose |
|---|---|---|
| `NeedsHumanBadge` | All four live demos | Identical visual treatment across demos. The teaching point lands only because of repetition. |
| `CascadeMatrix` | OrderFlow + RecruitFlow | Same component, different domain data. Visual repetition is deliberate. |
| `JSONInspector` | Planogram + Invoice | Toggleable raw-output panel. Off by default in prospect view. |
| `CostBadge` | Planogram + Invoice | Token usage + estimated cost. Cents tick up as analyses complete. |
| `AuditTrail` | RecruitFlow + Invoice + admin | Append-only event timeline. |
| `ResetButton` | Admin surfaces only | Renders per-demo + global reset. |
| `PipelineStages` | OrderFlow | Animated stage indicators driven by PubSub. |

## 6. Runtime semantics

### 6.1 Canonical data flow

```
User clicks button (LiveView)
        │
        ▼
LiveView handle_event → Pipeline.enqueue(...) → Oban job inserted, returns immediately
        │
        ▼  (LiveView paints "running" state, subscribes to PubSub topic)
Oban worker picks up job (per-demo queue)
        │
        ▼
Demo's Pipeline boundary:
   • calls impl/ for pure logic
   • calls AnthropicClient for AI
   • writes via Repo / Ash, wrapped in Ecto.Multi where transactional
   • PubSub-broadcasts at each meaningful stage
        │
        ▼
LiveView receives progress events → updates assigns → re-renders animated stages
        │
        ▼
Pipeline completes → final result persisted + final PubSub broadcast
        │
        ▼
LiveView swaps to result view (reads result from DB on receive — DB is source of truth)
```

PubSub carries progress; the DB carries truth. The LiveView never trusts in-flight messages for final state — only for animation. On reconnect mid-job, it re-queries the DB.

### 6.2 Concrete example — OrderFlow's `Generate order`

1. `phx-click="generate_order"` → `OrderFlow.enqueue_generate/0` → returns `:ok` immediately
2. Worker calls `OrderFlow.Pipeline.process_message(synthetic_message)`
3. Pipeline broadcasts `{:order_flow, :extract_complete, %{client_name, lines}}` → stage 1 lights up
4. `{:order_flow, :client_identified, %{client_id}}` → stage 2
5. `{:order_flow, :line_matched, %{line, step, confidence}}` per line → cascade visualization fills
6. `{:order_flow, :order_created, %{order_id}}` → LiveView swaps to result view (queries DB)

### 6.3 Failure modes

| What fails | Behavior |
|---|---|
| Anthropic timeout / 5xx | Oban retries (3 attempts, exponential backoff). Final failure writes `failed` outcome + reason to DB, broadcasts error, `AuditLog` records the chain. LiveView shows "AI call failed" panel with retry button (admin-only). |
| Malformed JSON from Claude | `ResilientJSONParser` salvages what it can. Result carries `incomplete: true` + recovered fields. UI surfaces partial result with "response was malformed; here's what we recovered" treatment. |
| Low-confidence / `needs_human` from AI | Not a failure — by design. Pipeline returns `%NeedsHumanDecision{needs_review?, reasons[]}` via the `Common.NeedsHuman` contract. `NeedsHumanBadge` renders identically across demos. |
| DB constraint violation in pipeline | `Ecto.Multi` rolls back. `AuditLog` write happens in a separate transaction so the failure is never lost. LiveView surfaces error. |
| LiveView disconnect / reconnect mid-pipeline | Subscription re-establishes on remount. LiveView re-queries DB for current state, then re-subscribes for future events. Missed in-flight animation isn't fatal. |
| Reset clicked mid-job | Admin reset cancels in-flight Oban jobs for the demo's queue (`Oban.cancel_all_jobs/1`), TRUNCATEs per-demo tables, re-seeds inside a transaction, broadcasts `:reset` topic. Open LiveViews for that demo re-mount to clean state. |
| Anthropic rate limit (429) | Oban backoff respects `Retry-After`. UI shows "AI is rate-limited, retrying in N seconds." |
| Oban queue stuck | Visible in Oban LiveDashboard (admin). Out of scope to engineer around at demo scale. |

**Cardinal rule:** failures are visible, not silent. A hung spinner reads as broken; an explicit "AI call failed, retrying" reads as honest engineering.

## 7. Testing

| Layer | Test approach | Coverage target |
|---|---|---|
| `impl/` (pure functions) | Unit tests, no DB, fast | **High** |
| Cascade matcher | Every step transitioned through + boundaries (exact found, fuzzy near-miss, client→global promotion, all-fail → LLM) | High |
| Resilient JSON parser | Truncation at every parse position (mid-string, mid-key, after `{`, after `[`, etc.) | High |
| State machine transitions (RecruitFlow) | All valid + invalid transitions enumerated | High |
| Verdict logic (Invoice) | Given canned AI response + thresholds, assert correct bucket | High |
| Boundaries (`Pipeline` modules) | Integration tests against `AnthropicClient.Mock` with seeded scenarios | Medium |
| Demo seeders + reset | Idempotency (run twice → identical state) + correctness | Medium |
| LiveView assigns | Targeted tests for critical state transitions (cascade visualizer, role switching, verdict re-evaluation on threshold change) | Light |
| Visual / E2E | Manual smoke before each AE-facing release. No Cypress / Wallaby. | Out of scope |
| Real Anthropic API | Not in CI. Fragile, expensive, irrelevant for a sales demo. | Out of scope |

**The `AnthropicClient.Mock` is load-bearing.** It returns canned responses keyed by prompt fingerprint + scenario name. Adding a new "Drop documents" scenario in Invoice means registering its expected mock response — that pattern is the testing spine.

## 8. Observability

- **Telemetry** fires on: every AI call (latency, tokens, cost), every cascade step + outcome, every state transition, every reset.
- **Phoenix LiveDashboard** mounted at `/admin/dashboard` (auth-gated). Useful for AE prep.
- **Oban dashboard** mounted at `/admin/oban`. Per-queue visibility is intentional — if a job hangs during a live demo, the AE can see it.

No external observability consumer (Honeycomb, Datadog, Sentry) wired up. The Telemetry events emit; nothing forwards them yet. Adding a consumer is a future-phase concern.

## 9. Build phases

| Phase | What gets built | Why this position |
|---|---|---|
| **0. Foundation** | Phoenix scaffold, Postgres + Oban free, `AnthropicClient` + `Mock`, Ash `SystemPrompt` + `AuditLog` resources, admin auth, demo-seeder/reset machinery, `Common` LiveView components stubbed, `CLAUDE.md` documenting the load-bearing patterns | Nothing builds without this. |
| **1. OrderFlow** | Full end-to-end: synthetic inbox, pipeline, cascade matcher, self-improving alias loop, developer toggle | Validates the most reusable `Common` piece (cascade matcher) on the simplest pipeline. |
| **2. Dashboard shell** | Value-framed tiles, global reset, `SystemPrompt` admin, `AuditLog` viewer | Needs at least one demo to link to. |
| **3. Invoice Approval** | 3-way match UI, threshold sliders, verdict-ratio panel, multi-doc Claude call | Reuses `ResilientJSONParser`; introduces multi-document calls. |
| **4. RecruitFlow** | Kanban, 18-state machine, transcript-gen-and-eval flow, CV cascade, scheduler ticker | Net-new patterns; no dependency on prior demos. |
| **5. Planogram** | Role switcher, vision call, cost badge, mobile QR handoff, parser-truncation toggle | Largest UI surface; leave for last when `Common` is mature. |
| **6. Restaurant Compliance** | TBD when brief lands. | Parked. |
| **7. Polish** | Neurony branding applied, copy review, AE walkthroughs, smoke tests, deploy | Brand and polish are last. Build first; paint later. |

Phases 0–2 are the non-negotiable v0 ("OrderFlow + dashboard"). Phases 3–6 each add one demo and are independent.

## 10. Out of scope (explicit non-goals)

- Real email / WhatsApp / Gmail / Whapi integration
- Real phone calls (ElevenLabs, Twilio, anyone)
- Real OCR pipeline beyond Claude vision
- Real ANAF / e-Factura XML / Romanian tax integration
- Multi-tenant isolation, customer accounts, signup flows, billing
- i18n (English only)
- iOS / Android native apps (mobile *web* only, only Planogram)
- Real-time multi-user collaboration
- Data export / reporting / cross-demo analytics dashboards
- E2E / Cypress / Wallaby / visual regression testing
- Load / performance testing
- Distributed Elixir / clustering / multi-node
- Production monitoring stack — only Telemetry events emitted, no consumer wired up
- Backups / DR — demo data is regenerable from seeds

## 11. Open questions

These don't block design; they block implementation phase 7 only.

1. **Restaurant Compliance brief** — pending from user.
2. **Neurony brand assets** — logo, palette, type system, brand guidelines.
3. **Concrete value / ROI numbers** for each dashboard tile's "before/after" copy. Placeholder copy lands until real numbers; AE can swap in lived examples per prospect.
4. **Hosting target** — Fly.io / Gigalixir / self-hosted / local-only. Affects deploy work.
5. **Showcase URL** — DNS + cert. Candidate hostnames TBD.

## 12. Next steps

1. User reviews this spec
2. On approval, invoke `writing-plans` skill to produce a phased implementation plan (one plan per build phase, starting with Phase 0)
3. Implementation phase 0 begins from that plan
