# Phase 2: Dashboard Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the value-framed tile launcher at `/` that replaces the Phoenix-default home page. Five tiles — OrderFlow (live), RecruitFlow / Planogram / Invoice Approval / Restaurant Compliance (Coming soon) — each with title, one-line value statement, ROI hook. Generalize the admin Reset UI to enumerate live demos via config so adding a new demo means editing one tile registry, not chasing hardcoded module lists.

**Architecture:** New `Showcase.Dashboard` context owns the tile registry — a list of `%Showcase.Dashboard.Tile{}` structs declaring per-demo metadata (id, title, description, ROI hook, status, route, seeder module). The registry lives in `Showcase.Dashboard.TileConfig` as a module attribute and is the single source of truth for "what demos exist." A `Showcase.Common.DemoSeeder.description/0` optional callback adds a one-line copy slot on each seeder. `ShowcaseWeb.DashboardLive` mounts at `/`. `ShowcaseWeb.Admin.ResetLive` is refactored to read seeders from `Dashboard.live_seeders/0` and render per-demo + global reset buttons. The existing `/order-flow` LiveView is unchanged; the dashboard is purely additive.

**Tech Stack:**
- Phase 0 foundation + Phase 1 OrderFlow merged into `main`
- Phoenix LiveView 1.x + function components
- Tailwind for layout (Phase 7 will apply Neurony branding)
- No new deps

**Reference spec:** `docs/superpowers/specs/2026-06-04-neurony-ai-showcase-design.md` §1 + §4

---

## File structure produced by this phase

```
lib/
  showcase/
    dashboard.ex                            # context: list_tiles/0, find_tile/1, live_tiles/0, live_seeders/0
    dashboard/
      tile.ex                               # %Tile{} struct
      tile_config.ex                        # all 5 tile entries
    common/
      demo_seeder.ex                        # MODIFY: add optional description/0 callback
    order_flow/
      seed.ex                               # MODIFY: implement description/0
  showcase_web/
    live/
      dashboard_live.ex                     # the / landing page
      admin/
        reset_live.ex                       # MODIFY: enumerate from Dashboard.live_seeders/0
    components/
      demo_tile.ex                          # function component (live vs coming_soon variants)
    router.ex                               # MODIFY: / → DashboardLive
    controllers/
      page_controller.ex                    # DELETE (Phoenix default; replaced by DashboardLive)
      page_html.ex                          # DELETE
      page_html/                            # DELETE

test/
  showcase/
    dashboard_test.exs                      # context tests
  showcase_web/
    live/
      dashboard_live_test.exs               # LiveView render tests
      admin/
        reset_live_test.exs                 # MODIFY/ADD: enumeration + per-demo reset tests
  showcase_web/controllers/
    page_controller_test.exs                # DELETE (route gone)
    error_html_test.exs                     # KEEP (Phoenix error pages)
    error_json_test.exs                     # KEEP
```

**Boundary rules** (per CLAUDE.md):
- `Dashboard.TileConfig` is pure data — no Repo, no IO. Compile-time module attribute.
- `Dashboard` context calls into `TileConfig` and exposes a clean API. No business logic.
- LiveViews use the public Dashboard API only; never reach into `TileConfig` directly.
- Reset orchestration still goes through `Showcase.Common.Reset.run/2` from Phase 0.

---

## Task 1: Add optional `description/0` callback to DemoSeeder + implement in OrderFlow.Seed

**Files:**
- Modify: `lib/showcase/common/demo_seeder.ex`
- Modify: `lib/showcase/order_flow/seed.ex`
- Modify: `test/showcase/order_flow/seed_test.exs`

### Step 1: Add optional callback declaration

Open `lib/showcase/common/demo_seeder.ex`. After the existing `@callback name() :: String.t()` declaration, add:

```elixir
  @doc """
  Optional. One-line description of the demo for the dashboard tile.
  Used as the value-framing copy on the launcher.

  If not implemented, the tile falls back to the demo name as its description.
  """
  @callback description() :: String.t()

  @optional_callbacks description: 0, oban_queue: 0
```

(The `oban_queue: 0` is already declared optional from Phase 0; keep it in the same `@optional_callbacks` line. If `@optional_callbacks` was already present with only `oban_queue: 0`, expand it to include both.)

### Step 2: Update OrderFlow.Seed test for description/0

Open `test/showcase/order_flow/seed_test.exs`. Add a test inside the existing `defmodule Showcase.OrderFlow.SeedTest do` block:

```elixir
  test "description/0 returns a one-line value-framing copy" do
    description = Seed.description()
    assert is_binary(description)
    # Sanity: short enough for a tile, contains a meaningful phrase
    assert String.length(description) > 20
    assert String.length(description) < 200
  end
```

### Step 3: Run failing

```bash
mix test test/showcase/order_flow/seed_test.exs
```

Expected: 1 failure for the new test (other 5 still pass).

### Step 4: Implement description/0 in OrderFlow.Seed

Open `lib/showcase/order_flow/seed.ex`. Find the `@impl true def name, do: "OrderFlow"` line and add after it:

```elixir
  @impl true
  def description do
    "Turn unstructured customer messages into structured orders, with the system getting smarter every time a human corrects it."
  end
```

### Step 5: Run until pass

```bash
mix test test/showcase/order_flow/seed_test.exs
```

Expected: 6 tests, 0 failures.

### Step 6: Commit

```bash
git add lib/showcase/common/demo_seeder.ex lib/showcase/order_flow/seed.ex test/showcase/order_flow/seed_test.exs
git commit -m "feat(common): add optional DemoSeeder.description/0 callback"
```

## Context

- Phase 2, Task 1. Branch: `phase-2-dashboard`. Starts off `main` at HEAD `b0b9fcf` (Phase 1 + seeds.exs wiring).
- The Phase 1 final reviewer flagged this missing callback as a Phase 2 prerequisite.

## Report

- Status, test count, commit SHA. Brief.

---

## Task 2: `Showcase.Dashboard.Tile` struct + `TileConfig` module

**Files:**
- Create: `lib/showcase/dashboard/tile.ex`
- Create: `lib/showcase/dashboard/tile_config.ex`
- Create: `test/showcase/dashboard/tile_config_test.exs`

### Step 1: Write failing test

Create `test/showcase/dashboard/tile_config_test.exs`:

```elixir
defmodule Showcase.Dashboard.TileConfigTest do
  use ExUnit.Case, async: true

  alias Showcase.Dashboard.{Tile, TileConfig}

  describe "all/0" do
    test "returns exactly 5 tiles in spec order" do
      tiles = TileConfig.all()
      assert length(tiles) == 5

      ids = Enum.map(tiles, & &1.id)
      assert ids == [:order_flow, :recruit_flow, :planogram, :invoice_approval, :restaurant_compliance]
    end

    test "every tile is a %Tile{} struct" do
      Enum.each(TileConfig.all(), fn tile ->
        assert match?(%Tile{}, tile)
      end)
    end

    test "every tile has required fields populated" do
      Enum.each(TileConfig.all(), fn tile ->
        assert is_atom(tile.id)
        assert is_binary(tile.title)
        assert is_binary(tile.description)
        assert is_binary(tile.roi_hook)
        assert tile.status in [:live, :coming_soon]
      end)
    end

    test "OrderFlow is live; the rest are coming_soon" do
      by_id = Enum.into(TileConfig.all(), %{}, &{&1.id, &1})

      assert by_id[:order_flow].status == :live
      assert by_id[:order_flow].path == "/order-flow"
      assert by_id[:order_flow].seeder == Showcase.OrderFlow.Seed

      Enum.each([:recruit_flow, :planogram, :invoice_approval, :restaurant_compliance], fn id ->
        assert by_id[id].status == :coming_soon
        assert by_id[id].path == nil
        assert by_id[id].seeder == nil
      end)
    end
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/dashboard/tile_config_test.exs
```

Expected: failures — modules don't exist.

### Step 3: Create the `Tile` struct

Create `lib/showcase/dashboard/tile.ex`:

```elixir
defmodule Showcase.Dashboard.Tile do
  @moduledoc """
  One entry in the dashboard tile registry.

  Tiles are declared in `Showcase.Dashboard.TileConfig` and exposed via the
  `Showcase.Dashboard` context.
  """

  @enforce_keys [:id, :title, :description, :roi_hook, :status]
  defstruct [
    :id,
    :title,
    :description,
    :roi_hook,
    :status,
    :path,
    :seeder
  ]

  @type status :: :live | :coming_soon

  @type t :: %__MODULE__{
          id: atom(),
          title: String.t(),
          description: String.t(),
          roi_hook: String.t(),
          status: status(),
          path: String.t() | nil,
          seeder: module() | nil
        }
end
```

### Step 4: Create the `TileConfig` registry

Create `lib/showcase/dashboard/tile_config.ex`:

```elixir
defmodule Showcase.Dashboard.TileConfig do
  @moduledoc """
  Compile-time registry of dashboard tiles. Single source of truth for
  "what demos the showcase ships."

  Adding a new demo: add an entry here, set status to `:live` once the
  demo's LiveView + Seed are wired.
  """

  alias Showcase.Dashboard.Tile

  @tiles [
    %Tile{
      id: :order_flow,
      title: "OrderFlow",
      description:
        "Turn unstructured customer messages into structured orders. The system gets smarter every time a human corrects a mismatch.",
      roi_hook: "Replaces hours of manual order re-keying per day with seconds of AI parsing.",
      status: :live,
      path: "/order-flow",
      seeder: Showcase.OrderFlow.Seed
    },
    %Tile{
      id: :recruit_flow,
      title: "RecruitFlow",
      description:
        "Phone-screen, score, and chase candidates through a complete recruitment funnel with a state-machine-driven pipeline.",
      roi_hook: "Recruiters intervene only on the ambiguous middle — everything else moves automatically.",
      status: :coming_soon,
      path: nil,
      seeder: nil
    },
    %Tile{
      id: :planogram,
      title: "Planogram Manager",
      description:
        "Retail shelf compliance audits done in seconds via a single vision call returning score, per-row breakdown, and suggested fixes.",
      roi_hook: "Replaces an afternoon of manual audit work with ~3-5¢ per shelf photo.",
      status: :coming_soon,
      path: nil,
      seeder: nil
    },
    %Tile{
      id: :invoice_approval,
      title: "Invoice Approval",
      description:
        "Three-way matching across contract, delivery note, and invoice. AI verdicts are explainable; configurable tolerances drive the routing.",
      roi_hook: "AP clerks see only the ambiguous middle; configuration is the dial.",
      status: :coming_soon,
      path: nil,
      seeder: nil
    },
    %Tile{
      id: :restaurant_compliance,
      title: "Restaurant Compliance",
      description:
        "Checklist-driven validation of actual restaurant photos against rules and reference images.",
      roi_hook: "Catches non-conformance in minutes, not weekly visits.",
      status: :coming_soon,
      path: nil,
      seeder: nil
    }
  ]

  @doc "All registered tiles in spec order."
  @spec all() :: list(Tile.t())
  def all, do: @tiles
end
```

### Step 5: Run until pass

```bash
mix test test/showcase/dashboard/tile_config_test.exs
```

Expected: 4 tests, 0 failures.

### Step 6: Compile clean check

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 7: Commit

```bash
git add lib/showcase/dashboard/ test/showcase/dashboard/
git commit -m "feat(dashboard): Tile struct + TileConfig registry with 5 demo entries"
```

## Context

- Phase 2, Task 2. Branch: `phase-2-dashboard`.
- The 5 tile entries match the design spec §1. OrderFlow is the only one currently `:live`; the rest become `:live` as their phases ship.

## Report

- Status, test count, commit SHA. Brief.

---

## Task 3: `Showcase.Dashboard` context

**Files:**
- Create: `lib/showcase/dashboard.ex`
- Create: `test/showcase/dashboard_test.exs`

### Step 1: Write failing tests

Create `test/showcase/dashboard_test.exs`:

```elixir
defmodule Showcase.DashboardTest do
  use ExUnit.Case, async: true

  alias Showcase.Dashboard
  alias Showcase.Dashboard.Tile

  describe "list_tiles/0" do
    test "returns all 5 tiles" do
      assert length(Dashboard.list_tiles()) == 5
    end
  end

  describe "live_tiles/0" do
    test "returns only :live tiles" do
      live = Dashboard.live_tiles()
      assert length(live) >= 1
      Enum.each(live, fn t -> assert t.status == :live end)
    end

    test "includes OrderFlow" do
      assert Enum.any?(Dashboard.live_tiles(), &(&1.id == :order_flow))
    end
  end

  describe "coming_soon_tiles/0" do
    test "returns only :coming_soon tiles" do
      cs = Dashboard.coming_soon_tiles()
      Enum.each(cs, fn t -> assert t.status == :coming_soon end)
    end

    test "excludes OrderFlow" do
      refute Enum.any?(Dashboard.coming_soon_tiles(), &(&1.id == :order_flow))
    end
  end

  describe "find_tile/1" do
    test "returns the tile when found" do
      assert %Tile{id: :order_flow} = Dashboard.find_tile(:order_flow)
    end

    test "returns nil when not found" do
      assert Dashboard.find_tile(:nonexistent) == nil
    end
  end

  describe "live_seeders/0" do
    test "returns seeder modules for all :live tiles" do
      seeders = Dashboard.live_seeders()
      assert Showcase.OrderFlow.Seed in seeders
    end

    test "excludes nil seeders from coming_soon tiles" do
      refute nil in Dashboard.live_seeders()
    end
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase/dashboard_test.exs
```

### Step 3: Implement the context

Create `lib/showcase/dashboard.ex`:

```elixir
defmodule Showcase.Dashboard do
  @moduledoc """
  Public context for the dashboard. Reads from `Showcase.Dashboard.TileConfig`
  and exposes a clean API for LiveViews and admin tools.

  Adding a new demo: edit `TileConfig`, not this module. This module's job is
  filtering and projecting the registry — not declaring demos.
  """

  alias Showcase.Dashboard.{Tile, TileConfig}

  @doc "All tiles in spec order."
  @spec list_tiles() :: list(Tile.t())
  def list_tiles, do: TileConfig.all()

  @doc "Only tiles marked :live (i.e., the demos that have shipped)."
  @spec live_tiles() :: list(Tile.t())
  def live_tiles, do: list_tiles() |> Enum.filter(&(&1.status == :live))

  @doc "Only tiles marked :coming_soon."
  @spec coming_soon_tiles() :: list(Tile.t())
  def coming_soon_tiles, do: list_tiles() |> Enum.filter(&(&1.status == :coming_soon))

  @doc "Find a tile by its id, or `nil`."
  @spec find_tile(atom()) :: Tile.t() | nil
  def find_tile(id) when is_atom(id), do: Enum.find(list_tiles(), &(&1.id == id))

  @doc """
  All seeder modules from live tiles. Used by the admin Reset orchestrator
  to enumerate seeders without hardcoding the list.
  """
  @spec live_seeders() :: list(module())
  def live_seeders do
    list_tiles()
    |> Enum.filter(&(&1.status == :live and not is_nil(&1.seeder)))
    |> Enum.map(& &1.seeder)
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase/dashboard_test.exs
```

Expected: 8 tests, 0 failures.

### Step 5: Commit

```bash
git add lib/showcase/dashboard.ex test/showcase/dashboard_test.exs
git commit -m "feat(dashboard): public context with list / live / coming_soon / find / live_seeders"
```

## Context

- Phase 2, Task 3. Branch: `phase-2-dashboard`. HEAD after T2.
- This is the public API. LiveViews call only `Dashboard.*`, never `TileConfig` directly.

## Report

- Status, test count, commit SHA.

---

## Task 4: `DemoTile` function component

**Files:**
- Create: `lib/showcase_web/components/demo_tile.ex`

Function components don't get unit tests — they're exercised through `DashboardLive` tests in Task 5.

### Step 1: Create the component

Create `lib/showcase_web/components/demo_tile.ex`:

```elixir
defmodule ShowcaseWeb.Components.DemoTile do
  @moduledoc """
  Renders one dashboard tile.

  Two visual variants based on `tile.status`:
    * `:live` — clickable, "Open →" link to `tile.path`, green "Live" badge.
    * `:coming_soon` — grayed out, no link, "Coming soon" badge.

  Both variants show title, description, and ROI hook.
  """

  use Phoenix.Component

  alias Showcase.Dashboard.Tile

  attr :tile, Tile, required: true

  def demo_tile(%{tile: %Tile{status: :live}} = assigns) do
    ~H"""
    <a
      href={@tile.path}
      class="block rounded-lg border border-zinc-200 bg-white p-6 shadow-sm transition hover:shadow-md hover:border-emerald-300"
    >
      <div class="flex items-start justify-between mb-3">
        <h3 class="text-lg font-semibold text-zinc-900">{@tile.title}</h3>
        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-emerald-300">
          <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
          Live
        </span>
      </div>
      <p class="text-sm text-zinc-700 mb-3">{@tile.description}</p>
      <p class="text-xs text-zinc-500 italic mb-4">{@tile.roi_hook}</p>
      <p class="text-sm font-medium text-emerald-700">Open →</p>
    </a>
    """
  end

  def demo_tile(%{tile: %Tile{status: :coming_soon}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-6 shadow-sm opacity-75">
      <div class="flex items-start justify-between mb-3">
        <h3 class="text-lg font-semibold text-zinc-700">{@tile.title}</h3>
        <span class="inline-flex items-center rounded-full bg-zinc-200 px-2 py-0.5 text-xs font-medium text-zinc-700 ring-1 ring-zinc-300">
          Coming soon
        </span>
      </div>
      <p class="text-sm text-zinc-600 mb-3">{@tile.description}</p>
      <p class="text-xs text-zinc-500 italic">{@tile.roi_hook}</p>
    </div>
    """
  end
end
```

### Step 2: Verify compile

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

Expected: clean.

### Step 3: Commit

```bash
git add lib/showcase_web/components/demo_tile.ex
git commit -m "feat(web): DemoTile function component with live + coming_soon variants"
```

## Context

- Phase 2, Task 4. Branch: `phase-2-dashboard`. HEAD after T3.
- Pattern-matches on `tile.status` for the two visual variants — clean dispatch via multi-clause function components.

## Report

- Status, compile result, commit SHA. Brief.

---

## Task 5: `ShowcaseWeb.DashboardLive` at `/`

**Files:**
- Create: `lib/showcase_web/live/dashboard_live.ex`
- Create: `test/showcase_web/live/dashboard_live_test.exs`
- Modify: `lib/showcase_web/router.ex` (change `/` from PageController.home to DashboardLive)
- Delete: `lib/showcase_web/controllers/page_controller.ex`
- Delete: `lib/showcase_web/controllers/page_html.ex`
- Delete: `lib/showcase_web/controllers/page_html/home.html.heex` (and the parent directory if empty)
- Delete: `test/showcase_web/controllers/page_controller_test.exs`

### Step 1: Write failing tests

Create `test/showcase_web/live/dashboard_live_test.exs`:

```elixir
defmodule ShowcaseWeb.DashboardLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the dashboard at /", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Neurony AI Showcase"
    assert html =~ "OrderFlow"
  end

  test "live tile shows 'Live' badge and links to its path", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Live"
    assert html =~ ~s(href="/order-flow")
  end

  test "coming-soon tiles show 'Coming soon' badge", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Coming soon"
    assert html =~ "RecruitFlow"
    assert html =~ "Planogram Manager"
    assert html =~ "Invoice Approval"
    assert html =~ "Restaurant Compliance"
  end

  test "all 5 tile descriptions are present", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    # Sample one phrase from each — the full strings are too long for clean matches
    assert html =~ "unstructured customer messages"  # OrderFlow
    assert html =~ "recruitment funnel"               # RecruitFlow
    assert html =~ "Retail shelf compliance"          # Planogram
    assert html =~ "Three-way matching"               # Invoice
    assert html =~ "restaurant photos"                # Restaurant Compliance
  end
end
```

### Step 2: Implement DashboardLive

Create `lib/showcase_web/live/dashboard_live.ex`:

```elixir
defmodule ShowcaseWeb.DashboardLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Dashboard
  alias ShowcaseWeb.Components.DemoTile

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Neurony AI Showcase")
     |> assign(:tiles, Dashboard.list_tiles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <header class="border-b border-zinc-200 bg-white">
        <div class="max-w-6xl mx-auto px-6 py-5 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-zinc-900">Neurony AI Showcase</h1>
            <p class="text-sm text-zinc-500 mt-1">
              Live demos of AI-mediated workflows we've built for clients.
            </p>
          </div>
          <a
            href="/admin/reset"
            class="text-sm text-zinc-500 underline hover:text-zinc-700"
          >
            Admin
          </a>
        </div>
      </header>

      <main class="max-w-6xl mx-auto px-6 py-10">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <DemoTile.demo_tile :for={tile <- @tiles} tile={tile} />
        </div>
      </main>
    </div>
    """
  end
end
```

### Step 3: Update the router

Open `lib/showcase_web/router.ex`. Find the public browser scope:

```elixir
scope "/", ShowcaseWeb do
  pipe_through :browser

  get "/", PageController, :home
  live "/order-flow", OrderFlow.InboxLive
  live "/order-flow/orders/:id", OrderFlow.OrderDetailLive
end
```

Replace `get "/", PageController, :home` with:

```elixir
live "/", DashboardLive
```

Final block:

```elixir
scope "/", ShowcaseWeb do
  pipe_through :browser

  live "/", DashboardLive
  live "/order-flow", OrderFlow.InboxLive
  live "/order-flow/orders/:id", OrderFlow.OrderDetailLive
end
```

### Step 4: Delete the now-unused Phoenix-default home page

```bash
rm -rf lib/showcase_web/controllers/page_controller.ex
rm -rf lib/showcase_web/controllers/page_html.ex
rm -rf lib/showcase_web/controllers/page_html/
rm -f test/showcase_web/controllers/page_controller_test.exs
```

### Step 5: Run until pass

```bash
mix test test/showcase_web/live/dashboard_live_test.exs 2>&1 | tail -5
```

Expected: 4 tests, 0 failures.

### Step 6: Full suite + compile check

```bash
mix test 2>&1 | tail -3
mix compile --warnings-as-errors 2>&1 | tail -3
```

Expected: full suite green (110 prior + 14 from T1-T3 + 4 from this task = ~128 tests). Note: removing `page_controller_test.exs` drops 1 test. Net counts may shift; just confirm 0 failures.

### Step 7: Smoke-test in dev

```bash
PORT=4321 mix phx.server &
SERVER_PID=$!
sleep 3
echo "GET / → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/)"
echo "GET /order-flow → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/order-flow)"
kill $SERVER_PID 2>/dev/null
```

Expected: both 200.

If the dev server is already running from a previous task (background PID earlier), Phoenix's code reloader will pick up the changes automatically; the smoke curls should still return 200 from the running instance.

### Step 8: Commit

```bash
git add lib/showcase_web/live/dashboard_live.ex test/showcase_web/live/dashboard_live_test.exs lib/showcase_web/router.ex
git add -u  # picks up the deleted files
git commit -m "feat(web): DashboardLive at / replaces Phoenix-default home page"
```

## Context

- Phase 2, Task 5. Branch: `phase-2-dashboard`. HEAD after T4.
- Phoenix 1.8's default scaffold created `PageController.home` + `home.html.heex`. Replacing with the dashboard LiveView; deleting the scaffold remnants.

## Report

- Status, test count (note Phoenix default count drops by 1; net should still be a positive delta), commit SHA, any HEEx adjustments.

---

## Task 6: Refactor `ShowcaseWeb.Admin.ResetLive` to enumerate from Dashboard

**Files:**
- Modify: `lib/showcase_web/live/admin/reset_live.ex`
- Create: `test/showcase_web/live/admin/reset_live_test.exs`

### Step 1: Write failing tests

Create `test/showcase_web/live/admin/reset_live_test.exs`:

```elixir
defmodule ShowcaseWeb.Admin.ResetLiveTest do
  use ShowcaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Showcase.OrderFlow.Schemas.SyntheticMessage
  alias Showcase.Repo

  defp authed_conn(conn),
    do: Plug.Conn.put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:changeme"))

  test "renders without crashing", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    assert html =~ "Reset"
    assert html =~ "OrderFlow"
  end

  test "shows a button per live demo", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    # OrderFlow is the only live demo right now — should appear once as a button
    assert html =~ "Reset OrderFlow"
  end

  test "shows a global 'Reset all demos' button", %{conn: conn} do
    {:ok, _view, html} = live(authed_conn(conn), "/admin/reset")

    assert html =~ "Reset all demos"
  end

  test "global reset triggers Common.Reset.run with all live seeders", %{conn: conn} do
    # Seed first so there's data to wipe
    Showcase.OrderFlow.Seed.seed()
    Repo.insert!(%SyntheticMessage{body: "manual", kind: "email", scenario: "test_only", client_hint: nil})

    assert Repo.aggregate(SyntheticMessage, :count) >= 5

    {:ok, view, _html} = live(authed_conn(conn), "/admin/reset")
    render_click(view, "reset_all", %{})

    # After reset: synthetic_messages count should be back to seed baseline (the 4 from MockPrompts)
    count = Repo.aggregate(SyntheticMessage, :count)
    assert count == 4
  end

  test "per-demo reset triggers Reset.run with only that seeder", %{conn: conn} do
    Showcase.OrderFlow.Seed.seed()
    Repo.insert!(%SyntheticMessage{body: "manual", kind: "email", scenario: "test_only", client_hint: nil})

    {:ok, view, _html} = live(authed_conn(conn), "/admin/reset")
    render_click(view, "reset_demo", %{"id" => "order_flow"})

    count = Repo.aggregate(SyntheticMessage, :count)
    assert count == 4
  end
end
```

### Step 2: Run failing

```bash
mix test test/showcase_web/live/admin/reset_live_test.exs 2>&1 | tail -5
```

Expected: failures — the current ResetLive only has a single "Reset OrderFlow" button hardcoded.

### Step 3: Replace `ResetLive`

Replace the entire contents of `lib/showcase_web/live/admin/reset_live.ex` with:

```elixir
defmodule ShowcaseWeb.Admin.ResetLive do
  use ShowcaseWeb, :live_view

  alias Showcase.Common.Reset
  alias Showcase.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset (admin)")
     |> assign(:live_tiles, Dashboard.live_tiles())
     |> assign(:last_action, nil)
     |> assign(:last_action_at, nil)}
  end

  @impl true
  def handle_event("reset_all", _params, socket) do
    case Reset.run(Dashboard.live_seeders()) do
      :ok ->
        {:noreply,
         socket
         |> assign(:last_action, "all demos")
         |> assign(:last_action_at, DateTime.utc_now())
         |> put_flash(:info, "All live demos reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reset_demo", %{"id" => id_string}, socket) do
    id = String.to_existing_atom(id_string)

    case Dashboard.find_tile(id) do
      %{seeder: seeder} = tile when not is_nil(seeder) ->
        case Reset.run([seeder]) do
          :ok ->
            {:noreply,
             socket
             |> assign(:last_action, tile.title)
             |> assign(:last_action_at, DateTime.utc_now())
             |> put_flash(:info, "#{tile.title} reset.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "#{tile.title} reset failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Unknown demo: #{id_string}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl">
      <h1 class="text-xl font-semibold">Reset demo data</h1>
      <p class="text-sm text-zinc-500 mt-2">
        Per-demo resets TRUNCATE that demo's tables + re-seed inside a transaction.
        In-flight Oban jobs on the demo's queue are cancelled first.
      </p>

      <div class="mt-6">
        <button
          type="button"
          class="rounded bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700"
          phx-click="reset_all"
          data-confirm="Reset ALL demos? This wipes all demo data."
        >
          Reset all demos
        </button>
      </div>

      <div class="mt-6">
        <h2 class="text-sm uppercase tracking-wide text-zinc-500 mb-2">Per-demo reset</h2>
        <ul class="space-y-2">
          <li :for={tile <- @live_tiles} class="flex items-center justify-between gap-4 border rounded p-3">
            <div>
              <p class="font-medium text-sm">{tile.title}</p>
              <p class="text-xs text-zinc-500">{tile.description}</p>
            </div>
            <button
              type="button"
              class="rounded bg-zinc-200 px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-300"
              phx-click="reset_demo"
              phx-value-id={tile.id}
              data-confirm={"Reset #{tile.title}? Wipes this demo's data."}
            >
              Reset {tile.title}
            </button>
          </li>
        </ul>
      </div>

      <%= if @last_action do %>
        <p class="text-xs text-zinc-500 mt-6">
          Last reset: <span class="font-mono">{@last_action}</span>
          at <span class="font-mono">{@last_action_at}</span>
        </p>
      <% end %>
    </div>
    """
  end
end
```

### Step 4: Run until pass

```bash
mix test test/showcase_web/live/admin/reset_live_test.exs 2>&1 | tail -5
```

Expected: 5 tests, 0 failures.

### Step 5: Full suite check

```bash
mix test 2>&1 | tail -3
```

Expected: full suite green.

### Step 6: Smoke-test in dev

```bash
PORT=4321 mix phx.server &
SERVER_PID=$!
sleep 3
echo "GET /admin/reset auth → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4321/admin/reset)"
kill $SERVER_PID 2>/dev/null
```

Expected: 200.

### Step 7: Commit

```bash
git add lib/showcase_web/live/admin/reset_live.ex test/showcase_web/live/admin/reset_live_test.exs
git commit -m "refactor(web): enumerate live seeders from Dashboard; add per-demo reset"
```

## Context

- Phase 2, Task 6. Branch: `phase-2-dashboard`. HEAD after T5.
- This addresses the Phase 1 reviewer's "hardcoded `@seeders` list" concern.
- Per-demo + global reset both go through `Showcase.Common.Reset.run/2`.

## Report

- Status, test count, commit SHA.

---

## Task 7: Final smoke test + phase-2 tag

Verification task. No new code.

### Step 1: Full test suite

```bash
mix test 2>&1 | tail -5
```

Expected: full suite green. (Net change from Phase 1: +14 from T1-T3 tests, +4 from T5 dashboard tests, +5 from T6 reset tests, −1 from removed page_controller_test = +22. From 110 → ~132 tests.)

### Step 2: Compile clean

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
```

### Step 3: Boot server

```bash
PORT=4321 mix phx.server &
SERVER_PID=$!
sleep 3
```

### Step 4: Verify all routes

```bash
echo "GET /                                  → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/)"
echo "GET /order-flow                        → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/order-flow)"
echo "GET /admin/reset auth                  → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4321/admin/reset)"
echo "GET /admin/dashboard auth              → $(curl -s -o /dev/null -w '%{http_code}' -u admin:changeme http://localhost:4321/admin/dashboard)"
echo "GET /admin/system-prompts noauth       → $(curl -s -o /dev/null -w '%{http_code}' http://localhost:4321/admin/system-prompts)"

# Confirm dashboard markup
curl -s http://localhost:4321/ | grep -c -E 'Neurony AI Showcase|OrderFlow|Coming soon'

kill $SERVER_PID 2>/dev/null
```

Expected:
- `/` → 200
- `/order-flow` → 200
- `/admin/reset` (auth) → 200
- `/admin/dashboard` (auth) → 200 or 302
- `/admin/system-prompts` (no auth) → 401
- grep count ≥ 3 (dashboard markup present)

### Step 5: Tag

```bash
git tag -a phase-2 -m "Phase 2 Dashboard complete: tile launcher at /, per-demo + global reset via config-driven seeder enumeration"
git tag -l 'phase-*'
```

Expected: `phase-0`, `phase-1`, `phase-2` all listed.

### Step 6: Commit history snapshot

```bash
git log --oneline phase-1..HEAD
```

Expected: clean linear history of T1-T6 commits since `phase-1` tag.

## Report

- Status
- Full test count + result
- All curl responses
- `git log --oneline phase-1..HEAD` output
- `phase-2` tag confirmation
- Anything unexpected

---

## Phase 2 acceptance criteria

When all tasks above are complete and committed:

- [ ] `mix test` green; full suite ~132 tests (was 110 at end of Phase 1)
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `GET /` renders the dashboard with 5 tiles (1 live OrderFlow + 4 coming-soon)
- [ ] OrderFlow tile is clickable; coming-soon tiles are visually disabled
- [ ] `GET /admin/reset` shows per-demo + global reset buttons
- [ ] Global reset re-seeds all live demos; per-demo reset wipes one demo
- [ ] `Showcase.Dashboard.live_seeders/0` enumerates from `TileConfig`, not hardcoded
- [ ] `Showcase.Common.DemoSeeder.description/0` is an optional callback
- [ ] `phase-2` tag in git history

The next plan (Phase 3: Invoice Approval) will be the second `:live` demo. Updating that tile in `TileConfig` from `:coming_soon` to `:live` becomes a one-line change.
