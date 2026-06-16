# Deploying to Railway

Step-by-step. ~15 min total in the Railway UI after the GitHub push.

## 0 · Prereqs

- A Railway account (`railway.app` — free trial gives ~$5 credit, after that ~$5/month minimum).
- This branch (`deploy/railway-self-serve`) merged to `main`, OR Railway connected directly to this branch.
- Your `ANTHROPIC_API_KEY`.

## 1 · Create the Railway project

1. Railway dashboard → **New Project** → **Deploy from GitHub repo**.
2. Pick `alexandruradulescu-neurony/aidemo`.
3. Branch: `main` (or the deploy branch).
4. Railway detects the `Dockerfile` and starts building. The first build takes 8-12 min (compiling Elixir + Erlang). Subsequent deploys are 2-4 min thanks to layer caching.

## 2 · Add Postgres

1. In the project, click **+ New** → **Database** → **Add PostgreSQL**.
2. Railway provisions a Postgres 16 instance and injects `DATABASE_URL` into your app service automatically. No manual wiring.

The `pg_trgm` extension required by OrderFlow is created by the migration at `priv/repo/migrations/*_enable_pg_trgm.exs` — no manual SQL needed.

## 3 · Add the uploads volume

The app writes user uploads (PDFs, photos) to `priv/static/uploads/`. Without a persistent volume, every deploy wipes them.

1. In the app service, click **Settings** → **Volumes** → **+ New Volume**.
2. **Mount path**: `/app/priv/static/uploads`
3. **Size**: 1 GB is plenty (each upload is <10 MB and Reset wipes them between prospect sessions).

## 4 · Set the env vars

In the app service, **Variables** tab. Add:

| Variable | Value | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Your real key |
| `ANTHROPIC_MODEL_DEFAULT` | `claude-haiku-4-5-20251001` | Or `claude-sonnet-4-5` if you want pricier/smarter |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` output | Generate locally; 64+ chars |
| `ADMIN_USER` | `admin` (or anything) | Used for `/admin/reset` etc |
| `ADMIN_PASS` | something stronger than `changeme` | This is the door to Reset |
| `PHX_SERVER` | `true` | Required — starts the HTTP server |
| `PHX_HOST` | `your-app.up.railway.app` | Or your custom domain |
| `PORT` | (leave to Railway default — it sets it) | |
| `POOL_SIZE` | `5` | Hobby Postgres has 100 max conns; 5 is generous for one instance |

`DATABASE_URL` is set automatically by the Postgres add-on. Don't touch it.

## 5 · First deploy

1. Hit **Deploy** (or push a commit — auto-deploy is on by default).
2. Watch the build log. The `preDeployCommand` in `railway.toml` runs `bin/migrate && bin/seed` before flipping traffic, so on first boot you'll see seed logs scroll past.
3. After ~10 min, the deploy goes green. Click the generated URL.

## 6 · Sanity-check

Hit each route via the Railway-generated URL and confirm 200:

- `/` — dashboard with 5 tiles
- `/order-flow` — 3 seeded Meesenburg emails
- `/invoice-approval` — 4 pre-analyzed bundles
- `/planogram` — 5 verification tasks (no photos yet — expected)
- `/restaurant-compliance` — 3 inspections (no photos yet — expected)
- `/admin/reset` — basic-auth prompt → use `ADMIN_USER` / `ADMIN_PASS`

## 7 · Custom domain (optional)

In the app service → **Settings** → **Networking** → **Custom Domain** → enter your subdomain, point a CNAME at the value Railway gives you. Then update `PHX_HOST` to match.

## 8 · "Reset demo" for prospects

The seeded state can drift as prospects use the app (delete emails, upload photos, etc.). To reset:

- **You**: hit `https://your-app/admin/reset`, BasicAuth with `ADMIN_USER`/`ADMIN_PASS`, click "Reset everything"
- **Prospects you trust**: share the `/admin/reset` URL + credentials in the trial email
- **Don't trust**: leave it; you reset when needed and don't share credentials

## 9 · Costs to expect

- **Railway compute**: ~$5-10/month (1 instance, Postgres add-on)
- **Railway volume**: 1 GB = $0.25/month
- **Anthropic tokens**: ~2-3¢ per Planogram/RC analysis, ~1¢ per OrderFlow extract. Budget $10-20/month for typical prospect exploration.

## 10 · Troubleshooting

**Build fails on `mix assets.deploy`**
- Almost always Node module resolution. Re-run; if persistent, check that `assets/package.json` is committed.

**App boots but `/` returns 502**
- Check `PHX_SERVER=true` is set. Without it, the release boots Erlang but doesn't start the HTTP server.

**`DATABASE_URL` raise on boot**
- The Postgres add-on isn't linked to this service. In Railway: app service → **Variables** → ensure `DATABASE_URL` references the Postgres service via `${{Postgres.DATABASE_URL}}`.

**Seeds didn't run / no data in tables**
- `preDeployCommand` may have failed silently. Open the deploy log and search for `Seeding`. If absent, SSH into the instance: `railway run /app/bin/seed`.

**Uploads disappear between deploys**
- Volume isn't mounted. Re-check step 3 — mount path must be exactly `/app/priv/static/uploads`.
