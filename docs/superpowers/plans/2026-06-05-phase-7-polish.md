# Phase 7 — Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the operator-facing polish that closes the showcase out: config documentation, a single model-override knob, read-only admin viewers for SystemPrompts and AuditLog, and Neurony brand application (colors + dashboard copy review).

**Architecture:**
- Config: one new env var `ANTHROPIC_MODEL_DEFAULT` swaps the hardcoded text model in 5 pipelines. Planogram vision stays pinned to Sonnet (Haiku can't do vision well). Read in `config/runtime.exs`, exposed via `Application.get_env(:showcase, :anthropic_default_model)`.
- Admin: two new read-only LiveViews replace the existing stubs. `SystemPromptsLive` reads from the `Showcase.Common.SystemPrompt` Ash resource (already defined in Phase 0). `AuditLogLive` reads from `Showcase.Common.AuditLog` (also Phase 0). Both gated by the existing `AdminBasicAuth` plug.
- SystemPrompt seeding: each demo seeds its active system prompts via a new `seed_system_prompts/0` step. This is reference data, not behavior change — pipelines keep using their inline strings. The admin viewer documents what's running.
- Brand: lightweight. Custom CSS variables in `assets/css/app.css` for Neurony colors. Dashboard copy review. Header gets a Neurony wordmark slot (logo asset can land later — placeholder text works for v1).

**Tech Stack:** Same as previous phases. No new deps.

---

## File Structure

**New:**
- `OPERATOR.md` — env vars reference, what to set + why
- `lib/showcase/common/system_prompt_seeder.ex` — shared helper used by per-demo seeds to upsert system prompt rows
- `lib/showcase_web/live/admin/system_prompts_live.ex` — replaces the stub
- `lib/showcase_web/live/admin/audit_log_live.ex` — replaces the stub
- `test/showcase_web/live/admin/system_prompts_live_test.exs`
- `test/showcase_web/live/admin/audit_log_live_test.exs`
- `test/showcase/common/system_prompt_seeder_test.exs`

**Modified:**
- `.env.example` — fleshed out with all 8+ env vars + comments
- `config/runtime.exs` — read `ANTHROPIC_MODEL_DEFAULT` and config the new app env key
- `lib/showcase/order_flow/extraction.ex` — replace `@model "claude-haiku-..."` with `default_model()` lookup
- `lib/showcase/order_flow/cascade/claude_fallback_step.ex` — same
- `lib/showcase/recruit_flow/phone_screen_pipeline.ex` — same
- `lib/showcase/recruit_flow/cascade/pdf_content_step.ex` — same
- `lib/showcase/invoice_approval/pipeline.ex` — same
- `lib/showcase/order_flow/seed.ex` — call `SystemPromptSeeder.upsert/3` for OrderFlow's prompts
- `lib/showcase/recruit_flow/seed.ex` — same
- `lib/showcase/invoice_approval/seed.ex` — same
- `lib/showcase/planogram/seed.ex` — same
- `assets/css/app.css` — Neurony color tokens
- `lib/showcase_web/components/layouts.ex` — header brand slot
- `lib/showcase_web/live/dashboard_live.ex` — copy review (subtle: tagline, footer)
- `lib/showcase/dashboard/tile_config.ex` — copy review

**Notes about the existing `.env.example`:**
The file exists but ships only 3 lines. Task 1 rewrites it completely.

---

## Tasks

### Task 1: `.env.example` + OPERATOR.md

**Files:**
- Modify: `.env.example`
- Create: `OPERATOR.md`

- [ ] **Step 1: Rewrite `.env.example`**

```bash
# .env.example — copy to .env (gitignored) and fill in values for your local dev,
# or set these as environment variables on your deploy host.
#
# REQUIRED IN PROD ONLY (the app raises at boot if missing):
#   DATABASE_URL, SECRET_KEY_BASE
# REQUIRED FOR REAL AI CALLS (otherwise the Mock answers in dev):
#   ANTHROPIC_API_KEY
# EVERYTHING ELSE HAS A SAFE DEFAULT.

# ─────────────────────────────────────────────────────────────────────
# AI
# ─────────────────────────────────────────────────────────────────────

# Anthropic API key. Without this, the Mock answers in dev (canned scenarios).
# Get one from https://console.anthropic.com/
ANTHROPIC_API_KEY=sk-ant-...

# Default Claude model for text-only demos (OrderFlow, RecruitFlow, Invoice).
# Planogram vision is pinned to claude-sonnet-4-5 regardless.
# Options: claude-haiku-4-5-20251001 | claude-sonnet-4-5
# Recommended: haiku for cheap demos, sonnet for higher quality.
ANTHROPIC_MODEL_DEFAULT=claude-haiku-4-5-20251001

# ─────────────────────────────────────────────────────────────────────
# Admin
# ─────────────────────────────────────────────────────────────────────

# Basic-auth credentials for /admin/* pages (reset, audit log, system prompts).
# CHANGE THESE BEFORE EXPOSING THE APP PUBLICLY.
ADMIN_USER=admin
ADMIN_PASS=changeme

# ─────────────────────────────────────────────────────────────────────
# Prod-only (release deploys)
# ─────────────────────────────────────────────────────────────────────

# Postgres connection string. ecto://USER:PASS@HOST:PORT/DBNAME
# DATABASE_URL=ecto://postgres:postgres@localhost/showcase_prod

# Phoenix session signing key — generate with `mix phx.gen.secret`
# SECRET_KEY_BASE=

# Public hostname used in URL generation (default: example.com)
# PHX_HOST=showcase.neurony.ro

# TCP port (default: 4000)
# PORT=4000

# Set to "true" to start the HTTP server in a release. mix phx.gen.release
# generates a bin/server script that sets this automatically.
# PHX_SERVER=true

# Postgres pool tuning
# POOL_SIZE=10
# ECTO_IPV6=false

# Optional clustering across nodes (libcluster)
# DNS_CLUSTER_QUERY=
```

- [ ] **Step 2: Create `OPERATOR.md`**

```markdown
# Operator guide — Neurony AI Showcase

This is the runtime reference for whoever deploys, demos, or maintains the
showcase app. Not for engineers (see `CLAUDE.md` + `AGENTS.md` for that).

## What this app is

A single Phoenix application bundling five demos behind a dashboard:

- **OrderFlow** — turn unstructured customer messages into structured orders
- **Invoice Approval** — three-way contract / delivery-note / invoice match
- **RecruitFlow** — 5-state recruitment funnel with AI phone screens + CV cascade
- **Planogram Manager** — retail shelf compliance via Claude vision
- **Restaurant Compliance** — deferred (tile shows "Coming soon")

You run one instance, click "Reset" between prospect meetings, and demos
restore to a known baseline state.

## Environment variables

Copy `.env.example` to `.env` (gitignored) for local dev, or set these
on your deploy host. The app raises at boot if a required prod variable
is missing.

| Variable | Purpose | When required | Default |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Real Claude calls | When you want real AI in dev or prod | empty (Mock answers) |
| `ANTHROPIC_MODEL_DEFAULT` | Default text model | Optional | `claude-haiku-4-5-20251001` |
| `ADMIN_USER` / `ADMIN_PASS` | Basic-auth on /admin | Always (change for prod) | `admin` / `changeme` |
| `DATABASE_URL` | Postgres connection | Prod only | none — raises |
| `SECRET_KEY_BASE` | Cookie signing | Prod only | none — raises |
| `PHX_HOST` | Public hostname | Prod | `example.com` |
| `PORT` | HTTP port | Prod | `4000` |
| `PHX_SERVER` | Start HTTP server in release | Releases | not set |
| `POOL_SIZE` | Postgres pool size | Prod tuning | `10` |
| `ECTO_IPV6` | Enable IPv6 connections | Prod (some clouds) | `false` |
| `DNS_CLUSTER_QUERY` | libcluster query | Multi-node prod | none |

### Generating SECRET_KEY_BASE

```bash
mix phx.gen.secret
```

Outputs a 64-byte base64 string. Use that as the value.

### Generating DATABASE_URL

For local dev (where Postgres.app runs as your OS user):

```
DATABASE_URL=ecto://$USER@localhost/showcase_dev
```

For prod (Render/Fly/your own server):

```
DATABASE_URL=ecto://app_user:secure_pass@db_host:5432/showcase_prod
```

## Running real Claude calls

By default in dev, the app calls real Anthropic when `ANTHROPIC_API_KEY` is
set. To force the mock answers (avoid burning tokens while iterating):

1. Unset `ANTHROPIC_API_KEY` (or set it to a clearly invalid value)
2. The app will fall back to `AnthropicClient.Mock` if you also override
   `config :showcase, :anthropic_client_impl, Showcase.Common.AnthropicClient.Mock`
   in `config/dev.exs` or via the runtime config.

In CI and tests the Mock is forced via `config/test.exs:47`. No real
API calls happen during the test suite.

## Picking a model

`ANTHROPIC_MODEL_DEFAULT` controls the text-only demos. Planogram vision
is hardcoded to Sonnet (Haiku can't do vision reliably).

| Model | Use it when | Cost per shelf photo | Cost per text demo call |
|---|---|---|---|
| `claude-haiku-4-5-20251001` | Default. Fast, cheap, "good enough" | n/a (no vision) | ~0.5¢ |
| `claude-sonnet-4-5` | Higher-quality reasoning, demo quality matters | ~3¢ | ~2¢ |

Cost estimates are approximate — see `lib/showcase/common/anthropic_client/live.ex`
for the pricing table the app uses for the on-screen cost badge.

## Admin pages

All routes under `/admin/*` are gated by HTTP Basic Auth (`ADMIN_USER` / `ADMIN_PASS`):

- `/admin/reset` — wipe + reseed per-demo data, or everything
- `/admin/system-prompts` — read-only viewer of active system prompts
- `/admin/audit-log` — append-only event log (state changes, verdict overrides)
- `/admin/dashboard` — Phoenix LiveDashboard (telemetry, queues, processes)

## Pre-demo checklist (1 minute before a prospect call)

1. Hit `/` — dashboard loads, all 4 live tiles render
2. Hit `/admin/reset` (BasicAuth: ADMIN_USER/ADMIN_PASS) → "Reset everything" → confirm
3. Verify each demo's landing route is 200:
   - `/order-flow` · `/invoice-approval` · `/recruit-flow` · `/planogram`
4. Run one analysis per demo and confirm the result renders
5. If you'll demo Planogram on a phone, generate a QR from the desktop and
   scan once before the prospect arrives (browsers cache the route)

## Where the data lives

- All app data: a single Postgres database (`showcase_dev` / `showcase_prod`)
- Mobile photo uploads (Planogram only): `priv/static/uploads/planogram/`
  — wiped on reset, gitignored
- Bundled reference images: `priv/static/images/<demo>/` — committed to repo
- Audit log: `common_audit_logs` table — read via `/admin/audit-log`
- System prompts: `common_system_prompts` table — read via `/admin/system-prompts`

## Cost guardrails

The cost badge on Planogram detail + Invoice detail views shows estimated
cents per call. If you want a hard cap, the simplest move is to leave
`ANTHROPIC_API_KEY` unset on shared / public deploys and let the Mock
answer — visitors see canned demo data, no money spent.

## Reset semantics

`/admin/reset` runs each live demo's `seed/0` inside a transaction:

1. Cancel any in-flight Oban jobs in that demo's queue
2. `TRUNCATE` the demo's tables (the seeder enumerates them explicitly)
3. Re-insert the baseline rows
4. Broadcast a `:reset` PubSub event so open LiveViews remount

Photo uploads on disk are wiped by the Planogram seed (it calls
`File.rm_rf!` on `priv/static/uploads/planogram/`).
```

- [ ] **Step 3: Verify both files render correctly**

Open `.env.example` and `OPERATOR.md` in a Markdown viewer (or `cat`) and skim for typos / broken tables.

- [ ] **Step 4: Commit**

```bash
git add .env.example OPERATOR.md
git commit -m "$(cat <<'EOF'
docs(polish): flesh out .env.example + add OPERATOR.md

Single operator-facing reference for env vars, model selection,
admin pages, and the pre-demo checklist. Leans on the existing
runtime.exs wiring rather than introducing new config machinery.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `ANTHROPIC_MODEL_DEFAULT` env var wiring

**Files:**
- Modify: `config/runtime.exs`, `config/config.exs`
- Modify: 5 pipeline modules (replace hardcoded `@model`)

- [ ] **Step 1: Add the runtime config**

In `config/runtime.exs`, after the existing `:anthropix` config block:

```elixir
# Default Claude model for text-only demos. Vision (Planogram) is pinned
# to Sonnet in lib/showcase/planogram/impl/vision_request.ex.
config :showcase,
  anthropic_default_model:
    System.get_env("ANTHROPIC_MODEL_DEFAULT") || "claude-haiku-4-5-20251001"
```

- [ ] **Step 2: Add the same key to `config/config.exs`**

So compile-time consumers (none today, but defensive) and `mix test` also see a value:

```elixir
config :showcase,
  anthropic_default_model: "claude-haiku-4-5-20251001"
```

Add this near the existing `config :showcase, ...` block.

- [ ] **Step 3: Add a one-line helper**

Create `lib/showcase/common/config.ex`:

```elixir
defmodule Showcase.Common.Config do
  @moduledoc """
  Centralized accessors for runtime config the demos read.
  """

  @spec default_model() :: String.t()
  def default_model do
    Application.get_env(:showcase, :anthropic_default_model, "claude-haiku-4-5-20251001")
  end
end
```

- [ ] **Step 4: Swap the 5 hardcoded `@model` uses**

In each of these 5 files, replace:

```elixir
@model "claude-haiku-4-5-20251001"
```

with a call to `Showcase.Common.Config.default_model()` at the request-build site (not as a module attribute — module attributes are compile-time, but `default_model/0` is runtime).

**Files to modify:**
- `lib/showcase/order_flow/extraction.ex`
- `lib/showcase/order_flow/cascade/claude_fallback_step.ex`
- `lib/showcase/recruit_flow/phone_screen_pipeline.ex`
- `lib/showcase/recruit_flow/cascade/pdf_content_step.ex`
- `lib/showcase/invoice_approval/pipeline.ex`

Example diff for `extraction.ex`:

```diff
-  @model "claude-haiku-4-5-20251001"
+  alias Showcase.Common.Config
...
   %Request{
-    model: @model,
+    model: Config.default_model(),
     ...
```

Make the same swap in all 5 files. Add the `alias Showcase.Common.Config` near the existing aliases.

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: All 273 tests + 1 property green. The hardcoded model is still `claude-haiku-4-5-20251001` (since `config/config.exs` has that default), so behavior doesn't change.

- [ ] **Step 6: Verify the env var actually overrides**

Run a quick smoke from `iex`:

```bash
ANTHROPIC_MODEL_DEFAULT=claude-sonnet-4-5 iex -S mix
```

Then in `iex`:

```elixir
Showcase.Common.Config.default_model()
# => "claude-sonnet-4-5"
```

Without the env var:

```bash
iex -S mix
```

Then:

```elixir
Showcase.Common.Config.default_model()
# => "claude-haiku-4-5-20251001"
```

- [ ] **Step 7: Update the Planogram admin tab**

In `lib/showcase_web/live/planogram/planogram_live.ex`, the `render_admin/1` function currently hardcodes `"claude-sonnet-4-5"` in the model display. Update it to show **both** the default (for text demos) and the Planogram-specific vision pin:

Find:
```elixir
<dt class="text-xs uppercase tracking-wide text-zinc-500">Active model</dt>
<dd class="font-mono">claude-sonnet-4-5</dd>
```

Replace with:
```elixir
<dt class="text-xs uppercase tracking-wide text-zinc-500">Vision model</dt>
<dd class="font-mono">claude-sonnet-4-5 (pinned)</dd>
```

And add a sibling row:
```elixir
<div>
  <dt class="text-xs uppercase tracking-wide text-zinc-500">Default text model</dt>
  <dd class="font-mono"><%= Showcase.Common.Config.default_model() %></dd>
</div>
```

- [ ] **Step 8: Commit**

```bash
git add config/ lib/showcase/common/config.ex \
        lib/showcase/order_flow/extraction.ex \
        lib/showcase/order_flow/cascade/claude_fallback_step.ex \
        lib/showcase/recruit_flow/phone_screen_pipeline.ex \
        lib/showcase/recruit_flow/cascade/pdf_content_step.ex \
        lib/showcase/invoice_approval/pipeline.ex \
        lib/showcase_web/live/planogram/planogram_live.ex
git commit -m "$(cat <<'EOF'
feat(config): ANTHROPIC_MODEL_DEFAULT env override for text models

5 pipelines now read Showcase.Common.Config.default_model/0 at request-build
time. Vision (Planogram) stays pinned to Sonnet because Haiku can't do vision.
Planogram admin tab now distinguishes vision-pin vs default-text-model.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: SystemPromptSeeder helper + per-demo seed integration (TDD on helper)

**Files:**
- Create: `lib/showcase/common/system_prompt_seeder.ex`
- Create: `test/showcase/common/system_prompt_seeder_test.exs`
- Modify: 4 per-demo `seed.ex` files

- [ ] **Step 1: Write the failing test**

File: `test/showcase/common/system_prompt_seeder_test.exs`

```elixir
defmodule Showcase.Common.SystemPromptSeederTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.{SystemPrompt, SystemPromptSeeder}

  describe "upsert/3" do
    test "creates a new row on first call" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_a", "You are a test prompt.")

      {:ok, [row]} = SystemPrompt.latest("test_demo", "section_a")
      assert row.body == "You are a test prompt."
      assert row.version == 1
    end

    test "is idempotent — same body → no new version" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_b", "Identical body.")
      :ok = SystemPromptSeeder.upsert("test_demo", "section_b", "Identical body.")

      rows = Showcase.Common.SystemPrompt |> Ash.read!() |> Enum.filter(&(&1.demo == "test_demo" and &1.section == "section_b"))
      assert length(rows) == 1
    end

    test "new body → new version" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_c", "Version 1 body.")
      :ok = SystemPromptSeeder.upsert("test_demo", "section_c", "Version 2 body.")

      rows = Showcase.Common.SystemPrompt |> Ash.read!() |> Enum.filter(&(&1.demo == "test_demo" and &1.section == "section_c"))
      assert length(rows) == 2

      {:ok, [latest]} = SystemPrompt.latest("test_demo", "section_c")
      assert latest.version == 2
      assert latest.body == "Version 2 body."
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase/common/system_prompt_seeder_test.exs`
Expected: FAIL — module not loaded.

- [ ] **Step 3: Write the implementation**

File: `lib/showcase/common/system_prompt_seeder.ex`

```elixir
defmodule Showcase.Common.SystemPromptSeeder do
  @moduledoc """
  Idempotent upsert helper for `Showcase.Common.SystemPrompt` rows.

  Used by each demo's seed to record the active system prompt as reference
  data — the admin viewer reads from these rows. Pipelines still use their
  inline string for now; this seeder makes the prompts *visible* in the
  admin without forcing a refactor of every pipeline.
  """

  alias Showcase.Common.SystemPrompt

  @spec upsert(String.t(), String.t(), String.t(), keyword()) :: :ok
  def upsert(demo, section, body, opts \\ []) do
    note = Keyword.get(opts, :note)

    case SystemPrompt.latest(demo, section) do
      {:ok, [latest]} ->
        if latest.body == body do
          :ok
        else
          create_new_version(demo, section, latest.version + 1, body, note)
        end

      {:ok, []} ->
        create_new_version(demo, section, 1, body, note)

      {:error, _} = err ->
        err
    end
  end

  defp create_new_version(demo, section, version, body, note) do
    SystemPrompt
    |> Ash.Changeset.for_create(:create, %{
      demo: demo,
      section: section,
      version: version,
      body: body,
      note: note
    })
    |> Ash.create!()

    :ok
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase/common/system_prompt_seeder_test.exs`
Expected: PASS — all 3 assertions green.

- [ ] **Step 5: Add per-demo seed_system_prompts calls**

For each of the 4 demos, add a `seed_system_prompts/0` helper and call it from `seed/0`. The prompts captured here should be the actual strings the pipelines use today (copy-paste the `@system_prompt` modules or the inline strings).

**`lib/showcase/order_flow/seed.ex`** — add inside `seed/0`, after the DB writes:

```elixir
seed_system_prompts()
```

And add the helper:

```elixir
defp seed_system_prompts do
  Showcase.Common.SystemPromptSeeder.upsert(
    "order_flow",
    "extraction",
    Showcase.OrderFlow.Extraction.system_prompt(),
    note: "Extracts client + line items from raw message text."
  )

  Showcase.Common.SystemPromptSeeder.upsert(
    "order_flow",
    "claude_fallback",
    Showcase.OrderFlow.Cascade.ClaudeFallbackStep.system_prompt(),
    note: "Last-resort product match when fuzzy + alias steps miss."
  )
end
```

(If `Extraction` and `ClaudeFallbackStep` keep their prompts as private functions, expose them as `def system_prompt`, do: ... — keep the implementation private with a public accessor.)

**`lib/showcase/recruit_flow/seed.ex`** — add inside `seed/0`:

```elixir
seed_system_prompts()
```

And the helper:

```elixir
defp seed_system_prompts do
  Showcase.Common.SystemPromptSeeder.upsert(
    "recruit_flow",
    "phone_screen",
    Showcase.RecruitFlow.PhoneScreenPipeline.system_prompt(),
    note: "Conducts a structured phone screen and returns transcript + eval."
  )

  Showcase.Common.SystemPromptSeeder.upsert(
    "recruit_flow",
    "cv_match",
    Showcase.RecruitFlow.Cascade.PdfContentStep.system_prompt(),
    note: "Matches a CV PDF to known candidates by free-text content."
  )
end
```

**`lib/showcase/invoice_approval/seed.ex`** — add:

```elixir
seed_system_prompts()
```

And:

```elixir
defp seed_system_prompts do
  Showcase.Common.SystemPromptSeeder.upsert(
    "invoice_approval",
    "approval",
    Showcase.InvoiceApproval.Pipeline.system_prompt(),
    note: "3-way matches contract + delivery notes + invoice, returns verdict."
  )
end
```

**`lib/showcase/planogram/seed.ex`** — add:

```elixir
seed_system_prompts()
```

And:

```elixir
defp seed_system_prompts do
  Showcase.Common.SystemPromptSeeder.upsert(
    "planogram",
    "vision_audit",
    Showcase.Planogram.Impl.VisionRequest.system_prompt(),
    note: "Vision call: audits shelf photo against expected planogram rows."
  )
end
```

(Make the `@system_prompt` module attribute accessible via `def system_prompt, do: @system_prompt` in `VisionRequest`.)

- [ ] **Step 6: Expose the prompts via public accessors**

Each of these modules needs a public `system_prompt/0` function that returns the prompt string. Add to each:

- `Showcase.OrderFlow.Extraction.system_prompt/0`
- `Showcase.OrderFlow.Cascade.ClaudeFallbackStep.system_prompt/0`
- `Showcase.RecruitFlow.PhoneScreenPipeline.system_prompt/0`
- `Showcase.RecruitFlow.Cascade.PdfContentStep.system_prompt/0`
- `Showcase.InvoiceApproval.Pipeline.system_prompt/0`
- `Showcase.Planogram.Impl.VisionRequest.system_prompt/0`

Convert the existing `@system_prompt` module attributes to public functions or expose them via accessor. Pattern:

```elixir
@system_prompt """
...
"""

@doc "The active system prompt text. Exposed for SystemPromptSeeder."
@spec system_prompt() :: String.t()
def system_prompt, do: @system_prompt
```

- [ ] **Step 7: Run the full suite**

Run: `mix test`
Expected: All tests still green. The seed tests will now also verify SystemPrompt rows are created.

- [ ] **Step 8: Seed the dev DB**

```bash
mix run -e "Showcase.Dashboard.live_seeders() |> Enum.each(& &1.seed())"
psql showcase_dev -c "SELECT demo, section, version, length(body) FROM common_system_prompts ORDER BY demo, section;"
```

Expected: 6 rows across the 4 demos.

- [ ] **Step 9: Commit**

```bash
git add lib/showcase/common/system_prompt_seeder.ex \
        test/showcase/common/system_prompt_seeder_test.exs \
        lib/showcase/{order_flow,recruit_flow,invoice_approval,planogram}/seed.ex \
        lib/showcase/{order_flow/extraction.ex,order_flow/cascade/claude_fallback_step.ex,recruit_flow/phone_screen_pipeline.ex,recruit_flow/cascade/pdf_content_step.ex,invoice_approval/pipeline.ex,planogram/impl/vision_request.ex}
git commit -m "$(cat <<'EOF'
feat(common): SystemPromptSeeder + per-demo seed integration

Each demo now seeds its active system prompts into common_system_prompts
on first run. Idempotent — same body skips, new body bumps version. The
admin /admin/system-prompts viewer (T4) reads from these rows so the
AE can see what's actually running without grepping the codebase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: SystemPromptsLive read-only viewer

**Files:**
- Replace: `lib/showcase_web/live/admin/system_prompts_live.ex` (currently a stub)
- Create: `test/showcase_web/live/admin/system_prompts_live_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase_web/live/admin/system_prompts_live_test.exs`

```elixir
defmodule ShowcaseWeb.Admin.SystemPromptsLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Seed all demos so SystemPrompt rows exist
    Showcase.Dashboard.live_seeders() |> Enum.each(& &1.seed())

    # Inject basic-auth header for /admin/*
    conn = Plug.Conn.put_req_header(conn, "authorization", basic_auth())
    {:ok, conn: conn}
  end

  defp basic_auth do
    user = Application.get_env(:showcase, :admin_user, "admin")
    pass = Application.get_env(:showcase, :admin_pass, "changeme")
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  describe "GET /admin/system-prompts" do
    test "lists active prompts grouped by demo", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")

      assert html =~ "System prompts"
      # All 4 live demos should appear
      assert html =~ "order_flow"
      assert html =~ "recruit_flow"
      assert html =~ "invoice_approval"
      assert html =~ "planogram"
    end

    test "renders the prompt body in a preformatted block", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")
      assert html =~ "<pre"
    end

    test "shows version + last-updated for each prompt", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/system-prompts")
      assert html =~ "v1" or html =~ "version"
    end
  end

  describe "without basic auth" do
    test "rejects with 401", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn() |> get("/admin/system-prompts")
      assert conn.status == 401
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase_web/live/admin/system_prompts_live_test.exs`
Expected: FAIL — the stub LiveView doesn't render the expected strings.

- [ ] **Step 3: Replace the stub LiveView**

File: `lib/showcase_web/live/admin/system_prompts_live.ex`

```elixir
defmodule ShowcaseWeb.Admin.SystemPromptsLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.SystemPrompt

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :groups, load_groups())}
  end

  defp load_groups do
    SystemPrompt
    |> Ash.read!()
    |> Enum.group_by(& &1.demo)
    |> Enum.map(fn {demo, prompts} ->
      # Keep only the latest version per section
      latest_per_section =
        prompts
        |> Enum.group_by(& &1.section)
        |> Enum.map(fn {_section, versions} ->
          Enum.max_by(versions, & &1.version)
        end)
        |> Enum.sort_by(& &1.section)

      {demo, latest_per_section}
    end)
    |> Enum.sort_by(fn {demo, _} -> demo end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-5xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">System prompts</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Read-only view of the active system prompts per demo. To edit, change the
              source module and re-seed (the seeder versions new bodies automatically).
            </p>
          </div>
          <a href="/admin/reset" class="text-sm text-zinc-500 underline">Admin home</a>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-6 py-6 space-y-8">
        <section :for={{demo, prompts} <- @groups} class="rounded border bg-white">
          <header class="border-b px-4 py-3">
            <h2 class="text-lg font-semibold"><%= demo %></h2>
            <p class="text-xs text-zinc-500"><%= length(prompts) %> active section(s)</p>
          </header>
          <div class="divide-y">
            <article :for={p <- prompts} class="px-4 py-4">
              <div class="flex items-center justify-between mb-2">
                <div>
                  <h3 class="font-medium"><%= p.section %></h3>
                  <p :if={p.note} class="text-xs text-zinc-500"><%= p.note %></p>
                </div>
                <div class="text-xs text-zinc-400">
                  v<%= p.version %> · updated <%= Calendar.strftime(p.updated_at, "%Y-%m-%d %H:%M") %>
                </div>
              </div>
              <pre class="bg-zinc-50 text-xs p-3 rounded whitespace-pre-wrap break-words"><%= p.body %></pre>
            </article>
          </div>
        </section>

        <p :if={@groups == []} class="rounded border bg-white p-6 text-center text-sm text-zinc-500">
          No system prompts seeded yet. Run <code>mix ecto.reset</code> and re-seed.
        </p>
      </main>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase_web/live/admin/system_prompts_live_test.exs`
Expected: PASS — all 4 assertions green.

- [ ] **Step 5: Manual smoke**

Visit `http://localhost:4321/admin/system-prompts` (BasicAuth: `admin/changeme`).
Expected: 4 demos, 6 sections total, each with body + version + timestamp.

- [ ] **Step 6: Commit**

```bash
git add lib/showcase_web/live/admin/system_prompts_live.ex \
        test/showcase_web/live/admin/system_prompts_live_test.exs
git commit -m "feat(admin): SystemPromptsLive read-only viewer"
```

---

### Task 5: AuditLogLive read-only viewer

**Files:**
- Replace: `lib/showcase_web/live/admin/audit_log_live.ex` (currently a stub)
- Create: `test/showcase_web/live/admin/audit_log_live_test.exs`

- [ ] **Step 1: Write the failing test**

File: `test/showcase_web/live/admin/audit_log_live_test.exs`

```elixir
defmodule ShowcaseWeb.Admin.AuditLogLiveTest do
  use ShowcaseWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Write a couple of synthetic audit entries
    Showcase.Common.AuditLog
    |> Ash.Changeset.for_create(:write, %{
      demo: "recruit_flow",
      entity_type: "application",
      entity_id: "1",
      event: "state_change",
      payload: %{from: "PENDING", to: "QUALIFIED"},
      actor: "alex@neurony.ro"
    })
    |> Ash.create!()

    Showcase.Common.AuditLog
    |> Ash.Changeset.for_create(:write, %{
      demo: "invoice_approval",
      entity_type: "bundle",
      entity_id: "42",
      event: "verdict_override",
      payload: %{from: "needs_human", to: "approve", reason: "AE override"},
      actor: "alex@neurony.ro"
    })
    |> Ash.create!()

    conn = Plug.Conn.put_req_header(conn, "authorization", basic_auth())
    {:ok, conn: conn}
  end

  defp basic_auth do
    user = Application.get_env(:showcase, :admin_user, "admin")
    pass = Application.get_env(:showcase, :admin_pass, "changeme")
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  describe "GET /admin/audit-log" do
    test "lists entries newest-first", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/audit-log")

      assert html =~ "Audit log"
      assert html =~ "recruit_flow"
      assert html =~ "invoice_approval"
      assert html =~ "state_change"
      assert html =~ "verdict_override"
      assert html =~ "alex@neurony.ro"
    end

    test "filters by demo when ?demo=<x>", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/audit-log?demo=recruit_flow")
      assert html =~ "state_change"
      refute html =~ "verdict_override"
    end

    test "renders empty state cleanly", %{conn: _conn} do
      # Wipe + new request
      Showcase.Common.AuditLog |> Ash.read!() |> Enum.each(&Ash.destroy!/1)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", basic_auth())

      {:ok, _view, html} = live(conn, "/admin/audit-log")
      assert html =~ "No audit entries"
    end
  end

  describe "without basic auth" do
    test "rejects with 401", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn() |> get("/admin/audit-log")
      assert conn.status == 401
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/showcase_web/live/admin/audit_log_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Replace the stub LiveView**

File: `lib/showcase_web/live/admin/audit_log_live.ex`

```elixir
defmodule ShowcaseWeb.Admin.AuditLogLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.AuditLog

  @page_size 50

  @impl true
  def mount(params, _session, socket) do
    demo = Map.get(params, "demo")
    {:ok,
     socket
     |> assign(:demo_filter, demo)
     |> assign(:entries, load_entries(demo))
     |> assign(:demos, distinct_demos())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    demo = Map.get(params, "demo")
    {:noreply,
     socket
     |> assign(:demo_filter, demo)
     |> assign(:entries, load_entries(demo))}
  end

  defp load_entries(nil) do
    AuditLog
    |> Ash.read!()
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(@page_size)
  end

  defp load_entries(demo) when is_binary(demo) do
    AuditLog
    |> Ash.read!()
    |> Enum.filter(&(&1.demo == demo))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(@page_size)
  end

  defp distinct_demos do
    AuditLog
    |> Ash.read!()
    |> Enum.map(& &1.demo)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Audit log</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Append-only event log. Newest first. Showing up to <%= @page_size %> entries.
            </p>
          </div>
          <a href="/admin/reset" class="text-sm text-zinc-500 underline">Admin home</a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-6">
        <nav class="mb-4 flex gap-2 items-center">
          <span class="text-xs uppercase tracking-wide text-zinc-500">Filter:</span>
          <a href="/admin/audit-log"
             class={["rounded px-2 py-1 text-xs", if(@demo_filter == nil, do: "bg-zinc-900 text-white", else: "bg-white border")]}>
            All
          </a>
          <a :for={demo <- @demos} href={"/admin/audit-log?demo=#{demo}"}
             class={["rounded px-2 py-1 text-xs", if(@demo_filter == demo, do: "bg-zinc-900 text-white", else: "bg-white border")]}>
            <%= demo %>
          </a>
        </nav>

        <p :if={@entries == []} class="rounded border bg-white p-6 text-center text-sm text-zinc-500">
          No audit entries yet.
        </p>

        <ol :if={@entries != []} class="rounded border bg-white divide-y">
          <li :for={entry <- @entries} class="px-4 py-3 flex gap-4 items-start">
            <div class="w-40 shrink-0 text-xs text-zinc-500 font-mono">
              <%= Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M:%S") %>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span class="rounded bg-zinc-100 px-2 py-0.5 text-xs"><%= entry.demo %></span>
                <span class="text-xs text-zinc-600"><%= entry.entity_type %> #<%= entry.entity_id %></span>
                <span class="font-medium"><%= entry.event %></span>
                <span :if={entry.actor} class="text-xs text-zinc-400">by <%= entry.actor %></span>
              </div>
              <pre :if={entry.payload != %{}}
                   class="bg-zinc-50 text-xs p-2 rounded overflow-x-auto"><%= Jason.encode!(entry.payload, pretty: true) %></pre>
            </div>
          </li>
        </ol>
      </main>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/showcase_web/live/admin/audit_log_live_test.exs`
Expected: PASS — 4 assertions green.

- [ ] **Step 5: Manual smoke**

1. Run the dev server
2. Visit `/recruit-flow`, transition an application (e.g., PENDING → QUALIFIED)
3. Visit `/admin/audit-log` → see the entry
4. Visit `/admin/audit-log?demo=recruit_flow` → only RF entries

- [ ] **Step 6: Commit**

```bash
git add lib/showcase_web/live/admin/audit_log_live.ex \
        test/showcase_web/live/admin/audit_log_live_test.exs
git commit -m "feat(admin): AuditLogLive read-only viewer with demo filter"
```

---

### Task 6: Neurony brand polish + dashboard copy review

**Files:**
- Modify: `assets/css/app.css`
- Modify: `lib/showcase_web/components/layouts.ex`
- Modify: `lib/showcase_web/live/dashboard_live.ex`
- Modify: `lib/showcase/dashboard/tile_config.ex` (copy only)
- Modify: `priv/static/images/logo.svg` (or add a placeholder Neurony wordmark)

- [ ] **Step 1: Add Neurony color tokens to CSS**

In `assets/css/app.css`, add at the top (after the `@import` lines if any):

```css
@theme {
  /* Neurony brand palette */
  --color-neurony-50:  oklch(0.97 0.02 270);
  --color-neurony-100: oklch(0.93 0.04 270);
  --color-neurony-500: oklch(0.55 0.20 270);
  --color-neurony-600: oklch(0.48 0.22 270);
  --color-neurony-700: oklch(0.40 0.20 270);
  --color-neurony-900: oklch(0.20 0.12 270);
}
```

(Adjust hue/chroma to match the Neurony deck if available. Until brand assets land, this is a placeholder palette in the indigo/violet range.)

- [ ] **Step 2: Replace Phoenix default header with Neurony brand**

In `lib/showcase_web/components/layouts.ex`, find the existing `def app(assigns)` and replace the `<header>` block:

```heex
<header class="border-b border-zinc-200 bg-white">
  <div class="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
    <a href="/" class="flex items-center gap-3">
      <span class="rounded bg-neurony-600 px-2 py-1 text-xs font-semibold text-white tracking-wider">
        NEURONY
      </span>
      <span class="text-sm font-medium text-zinc-700">AI Showcase</span>
    </a>
    <div class="flex items-center gap-3">
      <.theme_toggle />
      <a href="/admin/reset" class="text-xs text-zinc-500 underline">Admin</a>
    </div>
  </div>
</header>
```

(If the project doesn't actually use `Layouts.app` for the demos — they each have their own header — only update the dashboard layout. Verify by grepping for `Layouts.app` usage.)

- [ ] **Step 3: Dashboard copy review**

In `lib/showcase_web/live/dashboard_live.ex`, find the page header. Add a tagline:

```heex
<h1 class="text-4xl font-semibold tracking-tight">AI in production</h1>
<p class="mt-3 text-base text-zinc-600 max-w-2xl">
  Five working demos showing how Neurony bakes AI into real business workflows.
  Each one runs a real Claude pipeline against synthetic input — the engineering
  is the same as production code.
</p>
```

(Below the tagline, the existing tile grid stays.)

- [ ] **Step 4: Tile copy review**

In `lib/showcase/dashboard/tile_config.ex`, review each tile's `description` and `roi_hook`. Goal: every sentence ends with what the AE says out loud to the prospect. Tighten where bloated.

Specific edits (only change copy that reads awkwardly — leave good copy alone):

- **OrderFlow** description: "Turn unstructured customer messages into structured orders. The system gets smarter every time a human corrects a mismatch." → Keep, it's good.
- **OrderFlow** roi_hook: "Replaces hours of manual order re-keying per day with seconds of AI parsing." → Keep.
- **Invoice Approval** description: "Three-way matching across contract, delivery note, and invoice. AI verdicts are explainable; configurable tolerances drive the routing." → Keep.
- **Invoice Approval** roi_hook: "AP clerks see only the ambiguous middle; configuration is the dial." → Keep, this is a great line.
- **RecruitFlow** description: "Phone-screen, score, and chase candidates through a 5-state recruitment funnel with AI screens + CV cascade." → Trim to: "Phone-screen, score, and route candidates through a 5-state funnel — AI handles the volume."
- **Planogram Manager** description: "Retail shelf compliance audits done in seconds via a single vision call returning score, per-row breakdown, and suggested fixes." → Keep.
- **Restaurant Compliance** description: "Checklist-driven validation of actual restaurant photos against rules and reference images." → Keep.

Apply only the RecruitFlow trim. The rest stays.

- [ ] **Step 5: Run tests**

Run: `mix test`
Expected: All green. Dashboard test may need a copy update if it asserts the old RecruitFlow string — check `test/showcase_web/live/dashboard_live_test.exs` and `test/showcase/dashboard/tile_config_test.exs`.

- [ ] **Step 6: Manual smoke**

Visit `/` — verify:
- Neurony header (or wordmark) renders
- Tagline + supporting copy visible
- All 5 tiles render with updated copy
- Theme toggle still works
- Admin link goes to `/admin/reset`

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css \
        lib/showcase_web/components/layouts.ex \
        lib/showcase_web/live/dashboard_live.ex \
        lib/showcase/dashboard/tile_config.ex
git commit -m "$(cat <<'EOF'
feat(brand): Neurony color tokens + dashboard tagline + copy tweaks

Brand placeholder palette (indigo/violet range) until proper assets land.
Header swaps the Phoenix default for a NEURONY wordmark + AI Showcase tagline.
Dashboard gains a one-paragraph value framing above the tile grid.
RecruitFlow tile description tightened.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Final smoke + phase-7 tag

**Files:**
- Run full suite
- Tag commit

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests green. Phase 7 adds ~12 new tests, so the count should land around 285+.

- [ ] **Step 2: Start the dev server and walk through the full AE flow**

Run: `mix phx.server`

Browser checklist:
1. `http://localhost:4321/` — dashboard with Neurony header, tagline, 5 tiles (4 live + 1 coming soon)
2. Click each live tile → render successfully
3. `http://localhost:4321/admin/reset` (BasicAuth) → full reset → reload `/` → 4 baseline tiles
4. `http://localhost:4321/admin/system-prompts` → 6 prompt rows across 4 demos
5. `http://localhost:4321/admin/audit-log` → empty initially. Trigger a RecruitFlow transition → refresh → entry appears
6. `http://localhost:4321/admin/dashboard` → Phoenix LiveDashboard still works
7. Verify model env var: `ANTHROPIC_MODEL_DEFAULT=claude-sonnet-4-5 mix phx.server`; check `/planogram` admin tab shows "Default text model: claude-sonnet-4-5"

- [ ] **Step 3: Tag the phase**

Run:
```bash
git tag phase-7
git tag | grep phase
```

Expected output:
```
phase-0
phase-1
phase-2
phase-3
phase-4
phase-5
phase-7
```

(Phase 6 — Restaurant Compliance — is deferred; gap between phase-5 and phase-7 is intentional.)

- [ ] **Step 4: Stop here**

`finishing-a-development-branch` will be invoked next to handle the merge / PR / keep choice.

---

## Self-review checklist

- [x] **Operator infrastructure complete:** all env vars documented, model knob in place, admin viewers replace stubs
- [x] **No new behavior — polish only:** every code change is either docs, config, or read-only UI. No pipeline logic touched.
- [x] **Minimum-states preference respected:** no new state machines, no inflated enums
- [x] **CLAUDE.md rules:** `impl/` purity untouched, Common doesn't depend on demos, AI calls still via AnthropicClient
- [x] **Idempotent seeders:** SystemPromptSeeder bumps versions only on body change; safe to re-run
