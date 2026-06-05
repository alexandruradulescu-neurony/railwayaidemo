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
