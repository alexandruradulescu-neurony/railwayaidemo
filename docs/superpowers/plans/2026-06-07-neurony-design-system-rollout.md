# Neurony Design System Rollout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the official Neurony brand & design system (tokens, fonts, wordmark) across the Showcase frontend — foundation tokens plus refresh of dashboard, app shell, demo tile, and shared CTA/badge components.

**Architecture:** `tokens.css` (verbatim Figma export) is source of truth. Exposed to Tailwind 4 via `@theme` block and to DaisyUI via light-theme overrides — so utility classes (`bg-purple`, `text-ink`) and DaisyUI components (`btn-primary`, `alert-error`) both inherit brand from the same place. Per-demo internals are intentionally untouched.

**Tech Stack:** Phoenix 1.8 LiveView, Tailwind 4 + DaisyUI, plain CSS variables, Fira Sans + Montserrat via Google Fonts.

**Spec:** [`docs/superpowers/specs/2026-06-07-neurony-design-system-rollout-design.md`](../specs/2026-06-07-neurony-design-system-rollout-design.md)

---

## File map

**Create:**
- `assets/css/neurony-tokens.css` — copy of `/Users/alex/Downloads/Neurony-Brand-Assets/tokens.css`
- `priv/static/images/neurony/wordmark.svg` — copy of `neurony-wordmark.svg`
- `priv/static/images/neurony/icons/{cloud-download,feature-planet,magic-wand,phone-flip,productivity,progress-complete,search-dollar,smart-contract}.svg`

**Modify:**
- `assets/css/app.css` — replace placeholder `@theme` block, add `@import`, override DaisyUI light theme
- `lib/showcase_web/components/layouts/root.html.heex` — body class
- `lib/showcase_web/components/layouts.ex` — `app/1` fallback shell
- `lib/showcase_web/live/dashboard_live.ex` — header + hero
- `lib/showcase_web/components/demo_tile.ex` — both variants
- `lib/showcase_web/components/cost_badge.ex` — brand colors
- `lib/showcase_web/components/needs_human_badge.ex` — Neurony amber/green
- `lib/showcase_web/components/audit_trail.ex` — line color, ink text, purple actor names
- `lib/showcase_web/components/reset_button.ex` — Neurony red

---

## Task 1: Copy brand assets into project

**Files:**
- Create: `assets/css/neurony-tokens.css`
- Create: `priv/static/images/neurony/wordmark.svg`
- Create: `priv/static/images/neurony/icons/*.svg` (8 files)

- [ ] **Step 1: Copy tokens.css**

```bash
cp /Users/alex/Downloads/Neurony-Brand-Assets/tokens.css \
   assets/css/neurony-tokens.css
```

- [ ] **Step 2: Copy wordmark**

```bash
mkdir -p priv/static/images/neurony
cp /Users/alex/Downloads/Neurony-Brand-Assets/logos/neurony-wordmark.svg \
   priv/static/images/neurony/wordmark.svg
```

- [ ] **Step 3: Copy icons**

```bash
mkdir -p priv/static/images/neurony/icons
cp /Users/alex/Downloads/Neurony-Brand-Assets/icons/*.svg \
   priv/static/images/neurony/icons/
```

- [ ] **Step 4: Verify all 10 files landed**

Run:
```bash
ls assets/css/neurony-tokens.css \
   priv/static/images/neurony/wordmark.svg \
   priv/static/images/neurony/icons/*.svg | wc -l
```
Expected: `10`

- [ ] **Step 5: Commit**

```bash
git add assets/css/neurony-tokens.css priv/static/images/neurony/
git commit -m "feat(brand): vendor Neurony tokens, wordmark, and icons

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire Neurony tokens into Tailwind 4 `@theme`

**Files:**
- Modify: `assets/css/app.css` (replace lines 105–118 — the placeholder `@theme` block)

- [ ] **Step 1: Read the current app.css**

Run: `cat assets/css/app.css | head -130`

Locate the placeholder `@theme` block (currently has `--color-neurony-50/100/500/600/700/900`). It sits between the LiveView `@custom-variant` declarations and the trailing comment `/* This file is for your main application CSS */`.

- [ ] **Step 2: Add `@import` of vendored tokens at top of app.css**

Find the line `@source "../../lib/showcase_web";` near the top and add this immediately after it (before the `@plugin` lines):

```css
/* Neurony brand tokens — source of truth lives in neurony-tokens.css.
   Pulls in CSS variables AND the Google Fonts @import for Fira Sans + Montserrat. */
@import "./neurony-tokens.css";
```

- [ ] **Step 3: Replace the placeholder `@theme` block**

Find and replace this exact block (currently in `app.css`):

```css
@theme {
  --color-neurony-50:  oklch(0.97 0.02 270);
  --color-neurony-100: oklch(0.93 0.04 270);
  --color-neurony-500: oklch(0.55 0.20 270);
  --color-neurony-600: oklch(0.48 0.22 270);
  --color-neurony-700: oklch(0.40 0.20 270);
  --color-neurony-900: oklch(0.20 0.12 270);
}
```

with:

```css
/* ─────────────────────────────────────────────────────────────────────
   Neurony brand — Tailwind 4 utilities backed by neurony-tokens.css.
   Adds: bg-purple, bg-purple-soft, bg-ink, bg-ink-deep, bg-surface-lav,
         bg-surface-lav-2, bg-line, bg-green, bg-amber, bg-red, bg-cyan, bg-teal
         and their text-* / border-* counterparts, plus font-heading / font-body.
   ───────────────────────────────────────────────────────────────────── */
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

  /* Type families */
  --font-heading: "Fira Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-body:    "Montserrat", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
```

- [ ] **Step 4: Build assets to verify CSS compiles**

Run: `mix assets.build`

Expected: succeeds with no errors. If it fails on the `@import`, the path is relative to `app.css` — confirm `assets/css/neurony-tokens.css` exists.

- [ ] **Step 5: Commit**

```bash
git add assets/css/app.css
git commit -m "feat(brand): wire Neurony tokens into Tailwind 4 @theme

Replaces the placeholder neurony-* palette with the real brand tokens
(purple, ink, surface-lav, line, semantic accents) imported from
neurony-tokens.css. Exposes them as Tailwind utilities so existing
code can adopt bg-purple, text-ink, font-heading, etc.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Override DaisyUI light theme with Neurony palette

**Files:**
- Modify: `assets/css/app.css` (the `@plugin "../vendor/daisyui-theme" { name: "light"; ... }` block)

- [ ] **Step 1: Locate the light theme block**

It currently sets `--color-primary: oklch(70% 0.213 47.604);` (an orange) and other Phoenix-default values. The block starts at the line `@plugin "../vendor/daisyui-theme" {` followed by `name: "light";`.

- [ ] **Step 2: Replace the semantic color lines**

In the `name: "light"` block, replace the existing `--color-*` lines (keep the `--radius-*`, `--size-*`, `--border`, `--depth`, `--noise` lines untouched). Find these lines:

```css
  --color-base-100: oklch(98% 0 0);
  --color-base-200: oklch(96% 0.001 286.375);
  --color-base-300: oklch(92% 0.004 286.32);
  --color-base-content: oklch(21% 0.006 285.885);
  --color-primary: oklch(70% 0.213 47.604);
  --color-primary-content: oklch(98% 0.016 73.684);
  --color-secondary: oklch(55% 0.027 264.364);
  --color-secondary-content: oklch(98% 0.002 247.839);
  --color-accent: oklch(0% 0 0);
  --color-accent-content: oklch(100% 0 0);
  --color-neutral: oklch(44% 0.017 285.786);
  --color-neutral-content: oklch(98% 0 0);
  --color-info: oklch(62% 0.214 259.815);
  --color-info-content: oklch(97% 0.014 254.604);
  --color-success: oklch(70% 0.14 182.503);
  --color-success-content: oklch(98% 0.014 180.72);
  --color-warning: oklch(66% 0.179 58.318);
  --color-warning-content: oklch(98% 0.022 95.277);
  --color-error: oklch(58% 0.253 17.585);
  --color-error-content: oklch(96% 0.015 12.422);
```

and replace with these Neurony values (oklch approximations of brand hex):

```css
  /* Neurony brand — DaisyUI semantic overrides */
  --color-base-100: oklch(100% 0 0);                /* white */
  --color-base-200: oklch(97% 0.005 280);           /* surface-lav-2 #F4F5FA */
  --color-base-300: oklch(86% 0.025 275);           /* line #D3D5EA */
  --color-base-content: oklch(28% 0.04 285);        /* ink #2E2B41 */
  --color-primary: oklch(64.5% 0.205 281);          /* purple #8A79FB */
  --color-primary-content: oklch(100% 0 0);         /* white on purple */
  --color-secondary: oklch(28% 0.04 285);           /* ink */
  --color-secondary-content: oklch(100% 0 0);
  --color-accent: oklch(64.5% 0.205 281);           /* purple */
  --color-accent-content: oklch(100% 0 0);
  --color-neutral: oklch(28% 0.04 285);             /* ink */
  --color-neutral-content: oklch(100% 0 0);
  --color-info: oklch(78% 0.12 234);                /* cyan #63C1FF */
  --color-info-content: oklch(28% 0.04 285);        /* ink on cyan */
  --color-success: oklch(72% 0.21 144);             /* green #19C332 */
  --color-success-content: oklch(100% 0 0);
  --color-warning: oklch(82% 0.17 73);              /* amber #FEBC2E */
  --color-warning-content: oklch(28% 0.04 285);     /* ink on amber */
  --color-error: oklch(52% 0.246 27);               /* red #CD0503 */
  --color-error-content: oklch(100% 0 0);
```

- [ ] **Step 3: Rebuild assets**

Run: `mix assets.build`

Expected: succeeds.

- [ ] **Step 4: Boot dev server briefly to confirm CSS loads**

Run (foreground for 5 seconds, then Ctrl-C):
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
curl -sf http://localhost:4000/ > /dev/null && echo "OK" || echo "FAIL"
kill $SERVER_PID 2>/dev/null
```

Expected: `OK`. If `FAIL`, check `mix phx.server` output for stylesheet compile errors.

- [ ] **Step 5: Commit**

```bash
git add assets/css/app.css
git commit -m "feat(brand): override DaisyUI light theme with Neurony palette

btn-primary, alert-*, badge-* and other DaisyUI components now inherit
Neurony's purple/ink/lavender/green/amber/red automatically. Computed
oklch values approximate the brand hex codes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Apply brand body class in root layout

**Files:**
- Modify: `lib/showcase_web/components/layouts/root.html.heex` (the `<body>` tag)

- [ ] **Step 1: Locate the `<body>` tag**

Currently: `<body>` (no class).

- [ ] **Step 2: Replace with brand body class**

Change:
```heex
<body>
```
to:
```heex
<body class="font-body text-ink bg-white antialiased">
```

- [ ] **Step 3: Verify dashboard still loads**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
curl -sf http://localhost:4000/ | grep -q "font-body" && echo "OK body class" || echo "FAIL"
kill $SERVER_PID 2>/dev/null
```

Expected: `OK body class`.

- [ ] **Step 4: Commit**

```bash
git add lib/showcase_web/components/layouts/root.html.heex
git commit -m "feat(brand): apply font-body and text-ink to root body

Cascades Montserrat and Neurony ink color to every page; per-component
font-heading utilities override for headings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Refresh `Layouts.app/1` fallback shell

**Files:**
- Modify: `lib/showcase_web/components/layouts.ex` (the `def app(assigns)` function)

- [ ] **Step 1: Replace the `app/1` function body**

Find this current implementation (lines ~36–70 in `layouts.ex`):

```elixir
  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end
```

and replace with:

```elixir
  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <a href="/" class="flex items-center gap-3 text-ink">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`

Expected: succeeds. (The function isn't currently called by any LiveView — each demo renders its own shell — but it must still compile.)

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/layouts.ex
git commit -m "feat(brand): replace Phoenix-default Layouts.app shell with Neurony chrome

The function is the fallback layout (each demo renders its own header
inline). Brings it in line with brand: wordmark, line color, surface-lav
background, no Phoenix marketing links.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Refresh DashboardLive header + hero

**Files:**
- Modify: `lib/showcase_web/live/dashboard_live.ex` (the `render/1` function)
- Test: `test/showcase_web/live/dashboard_live_test.exs` (must still pass — no changes expected)

- [ ] **Step 1: Replace the `render/1` body**

Find the current `def render(assigns) do ... end` (lines 16–52) and replace with:

```elixir
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-lav-2">
      <header class="border-b border-line bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <a href="/" class="flex items-center gap-3 text-ink">
            <img src={~p"/images/neurony/wordmark.svg"} class="h-7" alt="Neurony" />
          </a>
          <a
            href="/admin/reset"
            class="text-sm text-ink/60 hover:text-purple transition-colors"
          >
            Admin
          </a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-12">
        <div class="mb-10">
          <p class="font-body font-bold text-sm uppercase tracking-wider text-purple">
            Neurony · AI Showcase
          </p>
          <h1 class="mt-2 font-heading font-bold text-5xl text-ink tracking-tight">
            AI in production
          </h1>
          <p class="mt-3 font-body text-lg text-ink/70 max-w-2xl">
            Five working demos showing how Neurony bakes AI into real business
            workflows. Each one runs a real Claude pipeline against synthetic
            input — the engineering is the same as production code.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <DemoTile.demo_tile :for={tile <- @tiles} tile={tile} />
        </div>
      </main>
    </div>
    """
  end
```

- [ ] **Step 2: Run dashboard tests**

Run: `mix test test/showcase_web/live/dashboard_live_test.exs`

Expected: 4 tests pass. The tests assert text content (`"Live"`, `"Coming soon"`, demo names, `"Neurony AI Showcase"` via page_title) — all preserved.

- [ ] **Step 3: Verify visually with dev server**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
curl -sf http://localhost:4000/ | grep -E '(wordmark|text-purple|font-heading)' | head -3
kill $SERVER_PID 2>/dev/null
```

Expected: at least 3 grep hits (wordmark image, eyebrow purple class, heading font class).

- [ ] **Step 4: Commit**

```bash
git add lib/showcase_web/live/dashboard_live.ex
git commit -m "feat(dashboard): apply Neurony wordmark, eyebrow, and brand typography

Header: wordmark image (recoloured via ink), Admin link in ink/60.
Hero: purple uppercase eyebrow, Fira Sans h1 \"AI in production\",
Montserrat lead. Page bg surface-lav-2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Refresh DemoTile component

**Files:**
- Modify: `lib/showcase_web/components/demo_tile.ex` (both `demo_tile/1` clauses)

- [ ] **Step 1: Replace the entire module**

Overwrite `lib/showcase_web/components/demo_tile.ex` with:

```elixir
defmodule ShowcaseWeb.Components.DemoTile do
  @moduledoc """
  Renders one dashboard tile.

  Two visual variants based on `tile.status`:
    * `:live` — clickable, "Open →" link to `tile.path`, green "Live" badge.
    * `:coming_soon` — surface-lav background, no link, neutral "Coming soon" badge.

  Both variants show title, description, and ROI hook.
  """

  use Phoenix.Component

  alias Showcase.Dashboard.Tile

  attr :tile, Tile, required: true

  def demo_tile(%{tile: %Tile{status: :live}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      class="block rounded-2xl border border-line bg-white p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
    >
      <div class="flex items-start justify-between mb-3">
        <h3 class="font-heading font-bold text-lg text-ink">{@tile.title}</h3>
        <span class="inline-flex items-center gap-1.5 rounded-full bg-green/10 px-2.5 py-0.5 text-xs font-medium text-green ring-1 ring-green/30">
          <span class="h-1.5 w-1.5 rounded-full bg-green"></span>
          Live
        </span>
      </div>
      <p class="font-body text-sm text-ink/80 mb-3">{@tile.description}</p>
      <p class="font-body text-xs italic text-ink/50 mb-4">{@tile.roi_hook}</p>
      <p class="font-body text-sm font-semibold text-purple">Open →</p>
    </a>
    """
  end

  def demo_tile(%{tile: %Tile{status: :coming_soon}} = assigns) do
    ~H"""
    <div class="rounded-2xl border border-line bg-surface-lav p-6 opacity-75">
      <div class="flex items-start justify-between mb-3">
        <h3 class="font-heading font-bold text-lg text-ink/70">{@tile.title}</h3>
        <span class="inline-flex items-center rounded-full bg-line/40 px-2.5 py-0.5 text-xs font-medium text-ink/60 ring-1 ring-line">
          Coming soon
        </span>
      </div>
      <p class="font-body text-sm text-ink/60 mb-3">{@tile.description}</p>
      <p class="font-body text-xs italic text-ink/50">{@tile.roi_hook}</p>
    </div>
    """
  end
end
```

- [ ] **Step 2: Run dashboard tests**

Run: `mix test test/showcase_web/live/dashboard_live_test.exs`

Expected: 4 tests pass. The tests look for text `"Live"`, `"Coming soon"`, `~s(href="/order-flow")`, descriptions — all present.

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/demo_tile.ex
git commit -m "feat(dashboard): restyle DemoTile with Neurony tokens

Live tile: white card, line border, rounded-2xl, font-heading title,
text-purple Open CTA, green/10 Live pill with green ring.
Coming-soon tile: surface-lav bg with line border, dimmed ink text,
neutral pill.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Refresh CostBadge component

**Files:**
- Modify: `lib/showcase_web/components/cost_badge.ex`

- [ ] **Step 1: Replace the module**

Overwrite with:

```elixir
defmodule ShowcaseWeb.Components.CostBadge do
  use Phoenix.Component

  alias Showcase.Common.AnthropicClient.Types.Usage

  attr :usage, Usage, required: true

  def cost_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 rounded border border-line bg-white px-2 py-1 text-xs text-ink/70">
      <span>{@usage.input_tokens + @usage.output_tokens} tok</span>
      <span class="text-ink/40">·</span>
      <span class="font-semibold text-purple">
        ≈ {:erlang.float_to_binary(@usage.cost_estimate_cents, decimals: 2)}¢
      </span>
    </span>
    """
  end
end
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/cost_badge.ex
git commit -m "feat(brand): restyle CostBadge with line border and purple accent

Cost figure now renders in brand purple to draw the eye; container
uses border-line + ink/70 for muted token count.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Refresh NeedsHumanBadge component

**Files:**
- Modify: `lib/showcase_web/components/needs_human_badge.ex`

- [ ] **Step 1: Replace the module**

Overwrite with:

```elixir
defmodule ShowcaseWeb.Components.NeedsHumanBadge do
  use Phoenix.Component

  alias Showcase.Common.NeedsHuman.Decision

  attr :decision, Decision, required: true
  attr :class, :string, default: ""

  def needs_human_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-medium",
      @decision.needs_review? && "bg-amber/15 text-ink ring-1 ring-amber/40",
      !@decision.needs_review? && "bg-green/10 text-green ring-1 ring-green/30",
      @class
    ]}>
      <%= if @decision.needs_review? do %>
        ⚠ Needs review
      <% else %>
        ✓ Confident
      <% end %>
    </span>
    """
  end
end
```

- [ ] **Step 2: Run any tests that exercise the badge**

Run: `mix test --include badge 2>/dev/null; mix test test/showcase_web/live/invoice_approval/`

Expected: existing invoice approval tests pass (the badge renders text, not classes).

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/needs_human_badge.ex
git commit -m "feat(brand): restyle NeedsHumanBadge with Neurony amber/green

Needs-review state uses brand amber with ink text; confident state
uses brand green. Ring colors match for cohesion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Refresh AuditTrail component

**Files:**
- Modify: `lib/showcase_web/components/audit_trail.ex`

- [ ] **Step 1: Replace the module**

Overwrite with:

```elixir
defmodule ShowcaseWeb.Components.AuditTrail do
  use Phoenix.Component

  attr :entries, :list, required: true

  def audit_trail(assigns) do
    ~H"""
    <ol class="space-y-2">
      <li :for={entry <- @entries} class="text-sm border-l-2 border-line pl-3">
        <p class="font-body font-medium text-ink">{entry.event}</p>
        <p class="font-body text-xs text-ink/50">{entry.inserted_at}</p>
      </li>
    </ol>
    """
  end
end
```

- [ ] **Step 2: Run admin audit log tests**

Run: `mix test test/showcase_web/live/admin/audit_log_live_test.exs`

Expected: tests pass (they assert on entry text, not on visual classes).

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/audit_trail.ex
git commit -m "feat(brand): restyle AuditTrail with line border and ink text

Replaces zinc divider with brand line color; event text in ink, timestamp
in ink/50.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Refresh ResetButton component

**Files:**
- Modify: `lib/showcase_web/components/reset_button.ex`

- [ ] **Step 1: Replace the module**

Overwrite with:

```elixir
defmodule ShowcaseWeb.Components.ResetButton do
  use Phoenix.Component

  attr :scope, :string, required: true, doc: ~s(Either "global" or a demo slug)
  attr :rest, :global

  def reset_button(assigns) do
    ~H"""
    <button
      type="button"
      class="rounded-lg bg-red px-3 py-2 font-body text-sm font-semibold text-white shadow-sm transition hover:bg-red/90 active:bg-red/95"
      phx-click="reset"
      phx-value-scope={@scope}
      data-confirm={"Reset #{@scope}? This wipes demo data."}
      {@rest}
    >
      Reset {@scope}
    </button>
    """
  end
end
```

- [ ] **Step 2: Run admin reset tests**

Run: `mix test test/showcase_web/live/admin/reset_live_test.exs`

Expected: tests pass — they target click behavior, not class strings.

- [ ] **Step 3: Commit**

```bash
git add lib/showcase_web/components/reset_button.ex
git commit -m "feat(brand): restyle ResetButton with Neurony red and brand typography

Brand red (#CD0503) on white, Montserrat semibold label, rounded-lg
with subtle shadow + hover/active states.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `mix test`

Expected: all tests pass. If any LiveView test asserts a class string we migrated (e.g. `assert html =~ "bg-zinc-50"`), open the file and update the assertion to the new class.

- [ ] **Step 2: Compile with warnings as errors**

Run: `mix compile --warnings-as-errors`

Expected: succeeds, no warnings.

- [ ] **Step 3: Build production assets**

Run: `mix assets.deploy`

Expected: succeeds, produces `priv/static/assets/css/app.css` and `app.js`.

- [ ] **Step 4: Boot dev server and curl each demo entry page**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
for path in / /order-flow /recruit-flow /planogram /invoice-approval; do
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000$path)
  echo "$path → $status"
done
kill $SERVER_PID 2>/dev/null
```

Expected: every path returns `200`.

- [ ] **Step 5: Curl admin pages with basic auth**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
for path in /admin/reset /admin/system-prompts /admin/audit-log; do
  status=$(curl -s -o /dev/null -w "%{http_code}" -u admin:changeme http://localhost:4000$path)
  echo "$path → $status"
done
kill $SERVER_PID 2>/dev/null
```

Expected: every path returns `200`.

- [ ] **Step 6: Spot-check that wordmark and brand classes ship in the rendered HTML**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
curl -s http://localhost:4000/ | grep -oE '(/images/neurony/wordmark\.svg|font-heading|text-purple|bg-surface-lav-2)' | sort -u
kill $SERVER_PID 2>/dev/null
```

Expected: all 4 patterns appear.

- [ ] **Step 7: If any test or compile failed, fix and re-commit before proceeding**

Most likely failure mode: a LiveView test contains an assertion like `assert html =~ "bg-zinc-50"`. Update the assertion to match the new class, commit as `test: update class assertion for Neurony brand`.

- [ ] **Step 8: Final commit if there's any straggler change**

If steps 1–6 all passed cleanly, there's nothing to commit. Otherwise:

```bash
git add -A
git commit -m "fix: post-rollout cleanup from verification pass

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Done state

All twelve tasks complete means:

1. `tokens.css`, wordmark, 8 icons vendored.
2. `app.css` imports tokens, exposes brand utilities, overrides DaisyUI light theme.
3. Root body uses `font-body text-ink bg-white antialiased`.
4. `Layouts.app/1` fallback shell uses Neurony chrome.
5. Dashboard renders wordmark + brand hero + tile grid on lavender background.
6. DemoTile both variants use brand tokens.
7. CostBadge, NeedsHumanBadge, AuditTrail, ResetButton use brand tokens.
8. `mix test` passes, `mix compile --warnings-as-errors` clean.
9. Every demo entry page and admin page returns 200.

Pages NOT touched (per scope decision): OrderFlow inbox/detail, RecruitFlow kanban/detail, Planogram task list/capture/detail, Invoice Approval queue/bundle, admin LiveView body content beyond shared components. They render with new fonts but keep current zinc/emerald colors — that's intentional and tracked as follow-up work in spec §9.
