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
| **OrderFlow** | 3 clients (Meesenburg Romania / Alexandru Erdei / Dragos Manolache), **130 products** (Meesenburg feronerie K-series + AXOR profile + named hardware) + 47 global aliases (`balama → BAL-USA-MARO`, `manere → K1001-07-n03`, etc.). **3 demo email scenarios** in Romanian: clean SKU order, informal Romanian (`balama`), and mixed SKU+informal. |
| **Invoice Approval** | 3 clients (Meesenburg / Erdei / Manolache), 3 contracts (full Romanian "Contract de furnizare" with 17 articles + Anexa 1 line items), **4 pre-analyzed bundles**: `clean_match` → APPROVE · `price_drift` → NEEDS_HUMAN · `qty_mismatch` → REJECT · `out_of_contract` → REJECT. |
| **Planogram Manager** | **2 reference planograms**: "Pharmacy OTC end-cap" (6 shelves, 23 SKUs) + "Natural juices aisle" (5 shelves, 10 SKUs). **5 pending verification tasks**: 3 pharmacy (Farmacia Tei Centru / Sensiblu Băneasa / Catena Plaza, scenarios compliant/minor/major) + 2 juices (Hypermarket Băneasa / Mega Image Centru, scenarios compliant/major). All due today. |
| **Restaurant Compliance** | 1 ruleset ("Mise-en-place standards") with ~1000-char policy text + 2 reference image paths. **3 pending inspections** at recognizable Bucharest restaurants: Caru' cu Bere / Hanu' lui Manuc / Bistro Ateneu, each with a named inspector, all due today. |
| **RecruitFlow** | Tile renders "Coming soon" on the dashboard, not clickable. Not seeded — `Dashboard.live_seeders/0` filters out non-live demos so no `rf_*` rows are inserted on Reset. |

System prompts for every live demo are written to `common_system_prompts` so they're visible at `/admin/system-prompts`.

---

## 4 · Assets the seeded data **points at**

The seed loads file paths into the database for reference images. **The files themselves are committed to the repo** under `priv/static/`:

```
priv/static/
├── images/
│   ├── neurony/                       # brand logo + wordmark (app shell)
│   ├── planogram/
│   │   ├── pharmacy_shelf_reference.jpg     ← seeded planogram #1
│   │   └── natural_juices_reference.jpg     ← seeded planogram #2
│   └── restaurant_compliance/
│       ├── reference_round_table_guide.jpg  ← ruleset reference #1
│       └── reference_two_person_guide.jpg   ← ruleset reference #2
└── uploads/                            # runtime upload dirs (gitignored)
    ├── order_flow/                     # compose-email PDF attachments
    ├── invoice_approval/               # invoice + aviz PDFs uploaded during demo
    └── planogram/                      # uploaded shelf photos
```

If you clone the repo and a seeded image is missing, that's a bug — open an issue. Everything the seed references resolves on a fresh clone.

`priv/static/uploads/` starts empty per environment; it fills as you use the demo. `mix run -e 'Showcase.Common.Reset.run!()'` wipes upload dirs too.

---

## 5 · Demo-day file drops (operator content, not in repo)

The operator brings the following files to a live demo. None are required to ship — every demo also has a no-attachment path — but they make the story stronger.

### 5.1 Invoice Approval — 4 PDFs

Generate these once with the Python+reportlab prompt in the **`ONBOARDING-pdfs/`** folder of your demo kit (or use the prompt at the bottom of this doc, section 9). Drop them anywhere on your machine — the **"Receive an invoice"** button in the app accepts file uploads via standard browser file picker.

| PDF | Belongs to client | Demo verdict |
|---|---|---|
| `factura-MSB-1042.pdf` | Meesenburg Romania (`comenzi@meesenburg.ro`) | APPROVE |
| `aviz-MSB-001.pdf` | Meesenburg Romania | APPROVE |
| `factura-AE-1187.pdf` | Alexandru Erdei (`alexandru.erdei@meesenburg.ro`) | NEEDS HUMAN (7% price drift) |
| `aviz-AE-007.pdf` | Alexandru Erdei | NEEDS HUMAN |

### 5.2 OrderFlow — handwritten / printed orders

Bring a couple of real PDFs of customer orders (Romanian or any language). The **"Write an email"** compose modal accepts PDF + image attachments. Claude reads them via native PDF document blocks — works with handwriting.

### 5.3 Planogram — shelf photos

Take fresh phone photos of shelves matching one of the 2 seeded planograms (pharmacy aisle OR juices aisle). The **Field Audits** view → click any pending task → upload your photo → Analyze. Claude vision compares against the planogram's `expected_rows` and produces a compliance score + per-row breakdown.

### 5.4 Restaurant Compliance — restaurant photos

Bring 3–5 real restaurant table-setting / mise-en-place photos. Open any pending inspection (Caru' cu Bere, Hanu' lui Manuc, Bistro Ateneu) → upload via the photos tile → Analyze. Claude checks each rule against the photos and ties violations to specific images.

None of these files need to be in the repo. `priv/static/uploads/` is gitignored and `Reset` clears it between prospects.

---

## 6 · Verifying the install

After `mix setup`:

```bash
# Should print 299+ tests, 0 failures
mix test

# Should show http://localhost:4321/ → 200 once started
PORT=4321 mix phx.server
```

Routes to spot-check (all should return 200):
- `/` — dashboard with 5 tiles in order: OrderFlow → Invoice Approval → Planogram → Restaurant Compliance → **RecruitFlow (Coming soon, not clickable)**
- `/order-flow` — 3 Romanian demo emails in the inbox, each with a status badge
- `/invoice-approval` — 4 bundles, each pre-analyzed with a status badge (Approved / Needs human / Rejected)
- `/planogram` — Manager view has 2 planogram cards with real reference images; Field Audits view has 5 pending tasks (3 pharmacy + 2 juices)
- `/restaurant-compliance` — 3 pending Bucharest inspections (Caru' cu Bere / Hanu' lui Manuc / Bistro Ateneu)
- `/restaurant-compliance/rulesets` — 1 ruleset with 2 reference images visible
- `/admin/reset` — basic-auth gated, lets you wipe + re-seed per demo or globally (default credentials: `admin` / `changeme`, override via `.env`)
- `/admin/system-prompts` — read-only view of every demo's active prompts

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

---

## 9 · Generating the Invoice Approval demo PDFs

Paste the prompt below into Claude on the web (any session with code interpreter / Python sandbox enabled) to produce all 4 demo PDFs in one go. Save the resulting zip locally and you can drop them into the **"Receive an invoice"** flow during the demo.

````
I need 4 PDF documents for a sales demo. They model a Romanian commercial workflow:
each delivery cycle produces a Contract → Aviz de însoțire a mărfii (delivery note)
→ Factură fiscală (invoice). Two bundles, four PDFs total.

Generate them using Python + reportlab and zip them at the end.

# Style guide for all documents
- A4 paper, ~2cm margins, sans-serif (Helvetica) body, slightly bolder Helvetica-Bold for headers
- Top header: supplier logo placeholder text "Neurony Demo SRL" in bold, with address +
  CUI line beneath
- Doc type label on the top right ("FACTURĂ FISCALĂ" in purple #7C3AED or
  "AVIZ DE ÎNSOȚIRE A MĂRFII" in amber #B45309), document number large + monospace
- Two-column "Furnizor"/"Beneficiar" (or "Expeditor"/"Destinatar" for aviz) blocks
- Line-item table with proper borders, light shaded header row
- Money columns right-aligned, two decimals, comma as thousands separator
- Romanian language ONLY for all labels

# Supplier (same for all 4 docs)
- Name: Neurony Demo SRL · CUI: RO99887766 · RC: J40/1234/2026
- Address: Str. Furnizor nr. 100, Sector 1, București
- IBAN: RO00 INGB 0000 0000 0000 0000 (ING Bank)

# Bundle 1 — CORRECT (Meesenburg Romania, all lines match → APPROVE in app)
Beneficiar: Meesenburg Romania · CUI: RO12345678 · Str. Industriei nr. 12, Sector 3, București

## aviz-MSB-001.pdf (AVZ-2026-001, livrat 15.05.2026)
| Cod          | Denumire                     | Cant. | Preț unit. |
| K1001-07-n03 | Mâner ușă AXOR alb 28x92     | 100   | 25,50      |
| K1001-11-n03 | Mâner ușă AXOR maro 28x92    | 50    | 25,50      |
| K3001-01-n03 | Colțar jos K1                | 200   | 8,20       |
| BAL-USA-MARO | Balamale ușă maro            | 30    | 45,00      |
| BIT-PH2-BOX  | Biți PH2 (cutie 20 buc)      | 20    | 18,00      |

## factura-MSB-1042.pdf (F-2026-1042, emisă 20.05.2026, scadență 20.06.2026)
Same 5 lines, same prices. Add TVA 19% column.
Subtotal 7.175,00 · TVA 1.363,25 · TOTAL 8.538,25 RON

# Bundle 2 — PARTIAL (Alexandru Erdei, line 1 invoice price 7% above contract → NEEDS HUMAN)
Beneficiar: Alexandru Erdei · CUI: RO12345678 · Str. Industriei nr. 12, Sector 3, București

## aviz-AE-007.pdf (AVZ-2026-007, livrat 20.05.2026)
| Cod           | Denumire                                 | Cant. | Preț unit. |
| K2001-06-n03  | Broască multipunct ac. mâner             | 50    | 120,00     |
| K5001-13-n03  | Cremon ușă tip K                         | 30    | 95,00      |
| COLT-JOS      | Colțar jos universal                     | 100   | 8,20       |
| BAL-ANTIFL    | Balamale antiflambaj 4-toc + ccv         | 20    | 35,00      |
| MEC-OB-2400   | Mecanism OB 2000-2400                    | 15    | 180,00     |

## factura-AE-1187.pdf (F-2026-1187, emisă 25.05.2026, scadență 25.06.2026)
Same 5 lines EXCEPT first row K2001-06-n03 is billed at **128,40 RON** (+7%).
Subtotal 13.490,00 · TVA 2.563,10 · TOTAL 16.053,10 RON

Generate all 4 PDFs and provide them in a single zip file `demo-bundle.zip`.
Make sure Romanian diacritics (ă, ș, ț, î, â) render correctly.
````

Drop the resulting 4 PDFs in any folder you'll have open during the demo. The app stores its own copy under `priv/static/uploads/invoice_approval/` once you click Send.
