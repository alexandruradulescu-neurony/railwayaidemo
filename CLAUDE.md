# Showcase — AI agent context

This project is the Neurony AI Sales Demo Showcase. Spec lives at
`docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md`. Read it first.

For general Phoenix 1.8 / Ash / Ecto usage rules see `AGENTS.md` (Phoenix's
auto-generated guidance, kept verbatim). This file (`CLAUDE.md`) is the
project-specific overlay — load-bearing rules, architectural decisions, and
testing policy.

## Load-bearing rules (do not violate)

### 1. `impl/` vs boundaries
- Pure functions live in `impl/` directories or `*_impl.ex` modules.
- They MUST NOT call `Repo`, `HTTPoison`, `Req`, or read the clock
  (`DateTime.utc_now/0`, `Date.utc_today/0`). The current time is supplied
  by the boundary as an argument.
- Boundaries (`*.Pipeline`, `Showcase.Common.Reset`, etc.) own `Ecto.Multi`,
  transactions, Oban enqueues, and all side effects.

### 2. `Common` is depended-on, never depends up
- `Showcase.Common.*` MUST NOT reference any per-demo module.
- Demos depend on `Showcase.Common`.
- Adding a per-demo concept (e.g., "Position" from RecruitFlow) to `Common`
  is a design smell — it pollutes the shared layer.

### 3. AI calls go through `Showcase.Common.AnthropicClient`
- Never call Anthropix (or whatever SDK) directly anywhere except in
  `Showcase.Common.AnthropicClient.Live`.
- Boundary code calls `AnthropicClient.call/2` — the runtime impl is swapped
  in tests via the `:anthropic_client_impl` app config.

### 4. Database is source of truth
- No GenServers for domain entities (Order, Application, VerificationTask,
  Invoice, etc.). Use Postgres + Ash/Ecto.
- GenServers are reserved for infrastructure: caches, rate limiters,
  transient progress state.

### 5. Tables are prefixed per demo
| Prefix     | Demo                            |
|------------|---------------------------------|
| `common_*` | shared (system_prompts, audit_log) |
| `of_*`     | OrderFlow                       |
| `rf_*`     | RecruitFlow                     |
| `pg_*`     | Planogram                       |
| `ia_*`     | Invoice Approval                |
| `rc_*`     | Restaurant Compliance           |

Cross-demo joins are forbidden by convention.

### 6. LLM responses go through `ResilientJSONParser`
- Never `Jason.decode!(response.text)`. Always `ResilientJSONParser.parse/1`.
- Truncation salvage is part of the contract — calling code must handle
  `:partial` results.

## Ash usage policy

Use Ash for: `SystemPrompt`, `AuditLog`, per-demo schemas where validation +
policies + admin UI are cheap wins.

Use plain Ecto + LiveView for: pipeline boundaries, LiveView assigns, reset
machinery, the cascade matcher.

## Testing

- `impl/` modules: unit tests. No DB, no async harness needed.
- Boundaries: integration tests against `AnthropicClient.Mock`.
- New AI scenarios: register them in `Mock.register/2` in the test setup.
- No real Anthropic calls in CI.
- No Cypress / Wallaby / visual E2E — manual smoke before AE-facing release.

## Common commands

```bash
mix test                  # full suite
mix test test/showcase/common/   # common infrastructure tests
mix ecto.migrate          # run new migrations
mix ash_postgres.generate_migrations --name <name>   # Ash → migration
mix phx.server            # dev server, port 4000
```

## Admin

- Routes under `/admin` are gated by `ShowcaseWeb.Plugs.AdminBasicAuth`.
- Credentials: `ADMIN_USER` / `ADMIN_PASS` env vars (default: admin/changeme).
- `/admin/dashboard` is Phoenix LiveDashboard.
