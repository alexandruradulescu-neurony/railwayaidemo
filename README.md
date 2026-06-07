# Neurony AI Sales Demo Showcase

Live, on-stage demonstrations of how Anthropic Claude works inside real
B2B workflows — for Neurony sales prospects.

Four live demos:

| Demo | Path | What it shows |
|---|---|---|
| **OrderFlow** | `/order-flow` | Gmail-style inbox; Claude extracts orders from emails + PDFs (Romanian, handwriting, mixed SKU/free text). Five-step cascade matcher learns from operator corrections. |
| **Invoice Approval** | `/invoice-approval` | Three-way matching: contract ↔ aviz de însoțire ↔ factură. Color-coded matrix per line, configurable thresholds, verdict per bundle. |
| **Planogram Manager** | `/planogram` | Mobile QR-handoff → shelf photo → Claude vision compliance score against the expected planogram. |
| **Restaurant Compliance** | `/restaurant-compliance` | Rule-by-rule mise-en-place audit. Photos + a verbatim policy text → pass/partial/fail per rule, photo-anchored violations. |

A fifth tile, **RecruitFlow**, is marked "Coming soon" — deferred until a
proper pitch story lands.

## Getting started

→ See **[ONBOARDING.md](./ONBOARDING.md)** for the 5-minute clone-to-running
walkthrough (system reqs, env vars, `mix setup`, what seeds where).

→ See **[OPERATOR.md](./OPERATOR.md)** for the runtime/demo-day operator
reference: ports, env vars, common troubleshooting.

→ See **[CLAUDE.md](./CLAUDE.md)** for the project-specific rules AI
agents (Claude Code, Cursor, etc.) follow when editing this codebase.

## Stack

Elixir 1.18 / OTP 28 · Phoenix 1.8 · LiveView 1.1 · Ash 3.27 · Ecto 3.14
· PostgreSQL 14+ with `pg_trgm` · Oban · Tailwind 4 + daisyUI.

Anthropic Claude is the only LLM; integration goes through
`Showcase.Common.AnthropicClient` (behaviour + Live/Mock impls) so tests
never hit the real API.
