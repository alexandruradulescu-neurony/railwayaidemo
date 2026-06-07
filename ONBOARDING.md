# Onboarding — Neurony AI Showcase

A new developer / demo operator pulling this repo for the first time. The goal: clone → fill in one secret → run → working demos in under 10 minutes.

For deeper docs see:
- **`OPERATOR.md`** — runtime reference, env vars, troubleshooting
- **`CLAUDE.md`** — project-specific rules for AI agents working on this code
- **`AGENTS.md`** — Phoenix 1.8 / Ash / Ecto conventions
- **`docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md`** — original design spec

---

## 1 · System requirements

| Need | Version | How to install on macOS |
|---|---|---|
| **Elixir** | `1.18.4` | `brew install mise && mise install elixir@1.18.4-otp-28` (or asdf equivalent) |
| **Erlang/OTP** | `28.5` | Comes with the mise/asdf install above |
| **PostgreSQL** | `14+` | `brew install postgresql@16 && brew services start postgresql@16` |
| **Git** | any recent | already installed |

The repo includes a `.tool-versions` file, so mise/asdf will pick the right versions automatically when you `cd` into the directory.

### Postgres extensions

`pg_trgm` is required (used by OrderFlow's fuzzy matcher). The migration at `priv/repo/migrations/*_enable_pg_trgm.exs` enables it automatically on `mix ecto.migrate` — you don't have to do anything manually as long as Postgres is running and accepting your user.

If the migration fails with a permissions error: connect to your Postgres superuser and run `CREATE EXTENSION IF NOT EXISTS pg_trgm;` on the showcase database manually, then re-run `mix ecto.migrate`.

---

## 2 · Three-minute happy path

```bash
git clone https://github.com/alexandruradulescu-neurony/aidemo.git
cd aidemo
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY=sk-ant-...
mix setup
PORT=4321 mix phx.server
```

Open <http://localhost:4321/> — the dashboard with 5 tiles should be live.

`mix setup` runs (in order):
1. `mix deps.get` — fetches Elixir deps
2. `mix ecto.create` — creates the `showcase_dev` Postgres database
3. `mix ecto.migrate` — applies all migrations (incl. pg_trgm, Oban tables, demo schemas)
4. `mix run priv/repo/seeds.exs` — runs every live demo's `Seed.seed()` once
5. `mix assets.setup` + `mix assets.build` — Tailwind + esbuild

If anything fails, run the individual step in isolation to see the error.

---

## 3 · What gets seeded out of the box

All four live demos populate themselves on first run. **No manual seeding step needed** beyond `mix setup`.

| Demo | Seeded data |
|---|---|
| **OrderFlow** | 6 clients (Meesenburg / Erdei / Manolache + legacy Acme/Beta/Gamma), 104 products (Meesenburg feronerie + 40+ global aliases), 1 client-scoped alias for Beta Industries, 3 demo email scenarios in Romanian (clean SKU / informal / mixed) |
| **Invoice Approval** | 3 clients (Meesenburg / Erdei / Manolache), 3 contracts (one per client with 5 line items + body), 4 demo bundles (clean / price drift / qty mismatch / out-of-contract) pre-analyzed on first open |
| **Planogram Manager** | 3 stores, 1 reference planogram, 3 verification tasks (compliant + minor + major issues) |
| **Restaurant Compliance** | 1 ruleset with mise-en-place rules (text + 2 reference image paths), 1 inspection |
| **RecruitFlow** | Tile shows "Coming soon" — its seed still runs, but the tile is not clickable from the dashboard |

System prompts for every live demo are also written to `common_system_prompts` so they're visible at `/admin/system-prompts`.

---

## 4 · Assets the seeded data **points at**

The seed loads file paths into the database for reference images. **The files themselves are committed to the repo** under `priv/static/`:

```
priv/static/
├── images/
│   ├── neurony/         # brand logo + wordmark (referenced in app shell)
│   ├── planogram/       # reference planogram + sample shelf photos (3 scenarios)
│   └── restaurant_compliance/
│                        # 2 reference table-setting JPGs
└── uploads/              # runtime upload destinations (gitignored)
    ├── order_flow/      # compose-email image + PDF attachments
    ├── invoice_approval/  # invoice + aviz PDFs uploaded during demo
    └── planogram/       # uploaded shelf photos
```

If you clone the repo and a demo image is missing, that's a bug — open an issue. Everything the seed references should resolve.

The `priv/static/uploads/` tree starts empty per environment; it fills as you use the demo. `mix run -e 'Showcase.Common.Reset.run!()'` wipes upload dirs too.

---

## 5 · Demo-day file drops (operator content, not in repo)

For a live pitch, the AE typically uploads a few PDFs to simulate "received" documents:

1. **Invoice Approval demo PDFs** — `factura-MSB-1042.pdf`, `aviz-MSB-001.pdf`, `factura-AE-1187.pdf`, `aviz-AE-007.pdf` (generated using the prompt in `docs/superpowers/`, or send-in-Slack). Use the **Receive an invoice** button to attach these.
2. **OrderFlow demo PDFs** — handwritten / printed orders (`comanda1.pdf`, etc.). Use **Write an email** + the file picker.
3. **Planogram shelf photos** — the AE takes a fresh photo or uploads a sample; attached on the Manager view.

None of these files need to be in the repo. They're attached at demo time and stored under `priv/static/uploads/` for the duration of the meeting. `Reset` clears them between prospects.

---

## 6 · Verifying the install

After `mix setup`:

```bash
# Should print 302+ tests, 0 failures
mix test

# Should show http://localhost:4321/ → 200 once started
PORT=4321 mix phx.server
```

Routes to spot-check:
- `/` — dashboard with 5 tiles in order OrderFlow → Invoice → Planogram → Restaurant → RecruitFlow (last, "Coming soon")
- `/order-flow` — 3 demo emails in the inbox
- `/invoice-approval` — 4 bundles, each with a status badge (Approved / Needs human / Rejected)
- `/planogram` — 3 verification tasks
- `/restaurant-compliance` — 1 inspection ruleset
- `/admin/reset` — basic-auth gated, lets you wipe + re-seed per demo or globally (default credentials: `admin` / `changeme`, override via `.env`)

---

## 7 · Common gotchas

**Migration fails with "extension pg_trgm not available"** → `psql showcase_dev` → `CREATE EXTENSION pg_trgm;` → re-run.

**Server starts but every demo throws Anthropix errors** → `.env` is missing or `ANTHROPIC_API_KEY` is wrong. Restart the server (Phoenix config is read at boot, not hot-reloaded).

**"compilation error: must restart server"** after `git pull` → `config/config.exs` or `mix.exs` changed. Kill the server (`Ctrl-C`, `a`), `mix deps.get`, restart.

**Stuck Oban jobs after a failure** → admin reset, or:
```bash
mix run -e 'import Ecto.Query; Showcase.Repo.delete_all(from j in Oban.Job, where: j.state == "discarded")'
```

**Want a clean slate per demo** → click "Reset" at `/admin/reset`. Per-demo (only OrderFlow, only Invoice…) or global.

---

## 8 · Production-ish deploys

Out of scope of this onboarding doc — see `OPERATOR.md` for env vars (`SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`, etc.) and the Phoenix `mix phx.gen.release` flow. The app is single-node, no clustering required for the demo use case.
