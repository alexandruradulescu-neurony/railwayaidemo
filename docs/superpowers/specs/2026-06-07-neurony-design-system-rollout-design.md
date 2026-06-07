# Neurony Design System Rollout — Design

**Date:** 2026-06-07
**Status:** Approved (pending written review)
**Owner:** Alexandru Rădulescu

---

## 1. Goal

Apply the official Neurony brand & design system across the Showcase frontend. The Figma export at `/Users/alex/Downloads/Neurony-Brand-Assets/` is the source: `tokens.css`, `neurony-wordmark.svg`, eight functional icons, and accompanying imagery. Recent commit `3cd916a` introduced placeholder indigo/violet tokens and a `NEURONY` text chip — both replaced here with the real palette, real wordmark, and real type stack (Fira Sans + Montserrat).

The Showcase is an AE-facing internal demo tool, not a marketing landing page. The brand sweep follows that posture: clean app shell, no marketing hero, no portrait/imagery assets.

## 2. Confirmed decisions

| Decision | Choice | Notes |
|---|---|---|
| Sweep depth | Foundation + key surfaces | Foundation = tokens, fonts, DaisyUI theme. Key surfaces = dashboard, layouts shell, demo tile, shared badge/CTA components. Per-demo internals get fonts for free, keep current colors. |
| Dashboard treatment | App-like, no marketing hero | Wordmark + eyebrow + h1 + lead + tile grid. No ink-deep hero band, no portrait/imagery. |
| Primary logo | `neurony-wordmark.svg` | Recolorable via `currentColor`. Renders ink on light, white on dark when needed. |
| Token layering | `tokens.css` is source of truth, exposed via Tailwind 4 `@theme` *and* via DaisyUI light theme overrides | Single brand refresh updates all three layers. |
| Font delivery | Google Fonts `<link>` in `<head>` with preconnect | Avoids render-blocking CSS `@import`. |
| Accent semantics | Override DaisyUI `--color-success/warning/error/info` with Neurony green/amber/red/cyan | DaisyUI components inherit brand automatically. |
| Out of scope | Per-page restyle of demo internals; hero/portrait imagery; dark theme | Tracked as follow-ups. |

## 3. Architecture

### 3.1 File layout

```
assets/css/
├── app.css                           # imports tokens, wires @theme + DaisyUI overrides
└── neurony-tokens.css                # copied verbatim from Neurony-Brand-Assets/tokens.css

priv/static/images/neurony/
├── wordmark.svg                      # copied from neurony-wordmark.svg
└── icons/                            # 8 single-path SVGs, all use currentColor
    ├── cloud-download.svg
    ├── feature-planet.svg
    ├── magic-wand.svg
    ├── phone-flip.svg
    ├── productivity.svg
    ├── progress-complete.svg
    ├── search-dollar.svg
    └── smart-contract.svg
```

Brand imagery (`hero-background.png`, `fde-portrait.png`, `problem-media.png`, `role-media.png`, `presentation-thumbnail.png`, `step-icon.png`) is **not** copied — those are marketing landing-page assets, not Showcase content.

### 3.2 Token plumbing (`assets/css/app.css`)

Replaces the placeholder `@theme` block at lines 105–118.

```css
/* 1. Source of truth — vanilla CSS variables from the Figma export. */
@import "./neurony-tokens.css";

/* 2. Expose brand tokens as Tailwind 4 utilities. */
@theme {
  /* Brand */
  --color-purple:        #8A79FB;
  --color-purple-stroke: #9747FF;
  --color-purple-soft:   #D062FF;
  --color-ink:           #2E2B41;
  --color-ink-deep:      #281A4C;
  --color-body-on-dark:  #E6E7F3;
  --color-line:          #D3D5EA;
  --color-surface-lav:   #EEEEFF;
  --color-surface-lav-2: #F4F5FA;
  --color-cyan:          #63C1FF;
  --color-teal:          #0FB4CA;
  --color-green:         #19C332;
  --color-amber:         #FEBC2E;
  --color-red:           #CD0503;

  /* Type families — drive `font-heading` and `font-body` utilities */
  --font-heading: "Fira Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-body:    "Montserrat", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

/* 3. DaisyUI light theme — override semantic tokens with brand values.
      hex → oklch computed during implementation. */
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  /* ...existing radii/size/border tokens kept... */
  --color-primary:         oklch(...);   /* purple #8A79FB */
  --color-primary-content: oklch(...);   /* white */
  --color-base-100:        oklch(...);   /* white */
  --color-base-200:        oklch(...);   /* surface-lav-2 #F4F5FA */
  --color-base-300:        oklch(...);   /* line #D3D5EA */
  --color-base-content:    oklch(...);   /* ink #2E2B41 */
  --color-success:         oklch(...);   /* green #19C332 */
  --color-warning:         oklch(...);   /* amber #FEBC2E */
  --color-error:           oklch(...);   /* red #CD0503 */
  --color-info:            oklch(...);   /* cyan #63C1FF */
}
```

The old placeholder `neurony-*` block is removed — `bg-neurony-600` in `dashboard_live.ex` migrates to `bg-purple` in step §4.3.

### 3.3 Font loading (`lib/showcase_web/components/layouts/root.html.heex`)

Added to `<head>` before the `app.css` `<link>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link
  href="https://fonts.googleapis.com/css2?family=Fira+Sans:wght@400;600;700&family=Montserrat:wght@400;500;600;700&display=swap"
  rel="stylesheet"
/>
```

Body class on `<body>`: `font-body text-ink bg-white antialiased`.

The `@import url(...)` at the bottom of `tokens.css` is redundant once the `<link>` is in `<head>` — fonts are already requested by the time the imported `@import` resolves. Stripping it is tracked as a follow-up (§9).

## 4. Component & layout changes

### 4.1 `lib/showcase_web/components/layouts.ex` `app/1`

Generic Phoenix scaffolding (Phoenix logo, "Get Started" CTA) replaced with a minimal Neurony shell:

- Header: wordmark left, optional right-slot nav.
- Body: `bg-surface-lav-2 min-h-screen`.
- Flash group unchanged (DaisyUI `alert-*` inherits brand via theme override).

Each demo's LiveView continues to render its own header inline. `Layouts.app` is the fallback shell only — it stays cosmetic-only here, no behavior change.

### 4.2 `lib/showcase_web/components/demo_tile.ex`

Both `:live` and `:coming_soon` variants restyled:

| Element | `:live` | `:coming_soon` |
|---|---|---|
| Container | `bg-white border border-line rounded-2xl shadow-card p-6` | `bg-surface-lav border border-line rounded-2xl p-6 opacity-75` |
| Title | `font-heading font-bold text-lg text-ink` | same, `text-ink/70` |
| Body | `font-body text-ink/80 text-sm` | `font-body text-ink/60 text-sm` |
| ROI hook | `text-xs italic text-ink/50` | same |
| CTA | `text-sm font-semibold text-purple` "Open →" | none |
| Status pill | green dot + "Live" in `bg-green/10 text-green` | neutral pill `bg-line/40 text-ink/60` "Coming soon" |
| Hover | `hover:-translate-y-0.5 hover:shadow-lg transition` | none |

### 4.3 `lib/showcase_web/live/dashboard_live.ex`

Header rewritten:

```heex
<header class="border-b border-line bg-white">
  <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
    <a href="/" class="flex items-center gap-3 text-ink">
      <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
    </a>
    <a href="/admin/reset" class="text-sm text-ink/60 hover:text-purple">Admin</a>
  </div>
</header>
```

Hero block:

```heex
<main class="max-w-6xl mx-auto px-6 py-12">
  <div class="mb-10">
    <p class="font-body font-bold text-sm uppercase tracking-wider text-purple">
      Neurony · AI Showcase
    </p>
    <h1 class="mt-2 font-heading font-bold text-5xl text-ink tracking-tight">
      AI in production
    </h1>
    <p class="mt-3 font-body text-lg text-ink/70 max-w-2xl">
      Five working demos showing how Neurony bakes AI into real business workflows…
    </p>
  </div>
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
    <DemoTile.demo_tile :for={tile <- @tiles} tile={tile} />
  </div>
</main>
```

Page wrapper: `min-h-screen bg-surface-lav-2`.

### 4.4 Shared components

| File | Change |
|---|---|
| `cost_badge.ex` | Pill with `border-line text-ink/70 bg-white`; cost figure in `text-purple font-semibold`. |
| `needs_human_badge.ex` | Amber chip — `bg-amber/15 text-amber-900 border border-amber/40`. |
| `audit_trail.ex` | Dividers `border-line`; actor names `text-purple`; body text `text-ink/80`. |
| `reset_button.ex` | Destructive button stays red (`bg-red text-white hover:bg-red/90`); secondary actions become `bg-white border border-line text-ink hover:bg-surface-lav`. |

### 4.5 Components NOT touched in this pass

`audit_trail.ex`'s parent admin pages, `cascade_matrix.ex`, `pipeline_stages.ex`, `json_inspector.ex`, `core_components.ex`, and all per-demo LiveViews. They inherit:

- Font family (body cascades from `<body class="font-body">`).
- DaisyUI semantic colors (`btn-primary`, `alert-*`, etc.) via theme override.

Existing `zinc-*`, `emerald-*`, `amber-*`, `red-*` utility classes are left intact — they look essentially identical to the Neurony accent palette and avoid a high-blast-radius find/replace.

## 5. Semantic mapping (key surfaces only)

Applied during refactor of the components listed in §4.

| Use | Old | New |
|---|---|---|
| Page bg | `bg-zinc-50` | `bg-surface-lav-2` |
| Card surface | `bg-white` | `bg-white` |
| Body text | `text-zinc-700/900` | `text-ink` |
| Muted text | `text-zinc-500/600` | `text-ink/60` |
| Hairline border | `border-zinc-200` | `border-line` |
| Primary CTA / link | `text-emerald-700` | `text-purple` |
| Live status pill | `bg-emerald-100 text-emerald-800` | `bg-green/10 text-green` |
| Headings | (browser default) | `font-heading` |
| Body | (browser default) | `font-body` |
| Eyebrow | (none) | `text-purple uppercase tracking-wider font-body font-bold` |

## 6. Testing

Per `CLAUDE.md`: no Cypress/Wallaby/visual E2E.

1. `mix test` — full suite passes. No logic change. If LiveView tests assert on class strings we're migrating, update those assertions inline (small number expected).
2. Manual smoke before merge:
   - Dashboard renders, wordmark visible, tiles styled, Live/Coming-soon pills correct.
   - Each demo's entry page loads with new fonts but otherwise unchanged.
   - Admin pages (`/admin/reset`, `/admin/prompts`, `/admin/audit`) load with brand via shared components.
   - Font fallback: block `fonts.googleapis.com` in devtools, confirm `system-ui` fallback renders cleanly.
   - Responsive: dashboard at 375px, 768px, 1280px.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Google Fonts unavailable on demo day | `system-ui` fallback in token stack — page never goes unrendered. |
| DaisyUI oklch shift breaks an existing `btn-primary` somewhere | Caught in manual smoke #1–3. Patch inline if found. |
| LiveView tests assert on `zinc-*` / `emerald-*` classes | Expected on a small number; fix as encountered. |
| Wordmark contrast on white | `#2E2B41` on `#FFFFFF` ≈ 13.8:1 — well above AA. |

## 8. Rollback

Single feature branch `claude/charming-jepsen-960dad`. No DB or schema changes, no Oban migrations. `git revert` is one command.

## 9. Out of scope (explicit non-goals)

- Per-page restyling of demo internals (OrderFlow, RecruitFlow, Planogram, Invoice Approval, Restaurant Compliance, admin pages beyond shared components).
- Brand imagery integration (`hero-background.png`, `fde-portrait.png`, `problem-media.png`, `role-media.png`, `presentation-thumbnail.png`, `step-icon.png`).
- Dark theme — already pinned to light per commit `e9aec33`.
- Stripping the redundant `@import` inside `neurony-tokens.css`.
- Migrating `core_components.ex` away from Phoenix defaults.

Each can be picked up as a separate spec when the time comes.
