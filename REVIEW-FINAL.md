---
phase: post-fix-adversarial
reviewed: 2026-06-08
depth: deep
files_reviewed: 48
status: issues_found
findings:
  blocking: 0
  high: 2
  medium: 4
  low: 5
  total: 11
---

# Final Adversarial Review — Pre-Demo

Verdict: **ship it**. No BLOCKING bugs found. The two HIGH items are latent test flakiness (won't surface tomorrow) and a single demo-visible UX wart. The fixes from the two prior PRs are mostly clean. Detailed findings below.

## HIGH

### HI-A: `async: true` tests share global Mock ETS, latent flake

**Files:**
- `test/showcase/common/anthropic_client/mock_test.exs:2` (`async: true`)
- `test/showcase/order_flow/cascade/claude_fallback_step_test.exs:2` (`async: true`)

Both files call `Mock.reset()` in `setup`, which wipes the **shared, named** ETS table `:anthropic_client_mock`. When the ExUnit scheduler interleaves them, one file's reset can land between another file's register and assert.

The race doesn't always trigger (timing-dependent on # cores + load), which is why the suite reports 0 failures today. The existing comment in `extraction_test.exs:2-3` ("concurrent test files calling Mock.reset() race with our Mock.register here. Run sync.") flags the exact same pattern but stops at fixing one file.

**Fix:** flip both files to `async: false`. Trivial. The `mock_test.exs` one in particular is at risk because it tests the mock infrastructure itself — flakiness here will be the worst kind of red herring.

### HI-B: "Send to ERP" double-flash on demo-day double-click

**File:** `lib/showcase_web/live/order_flow/inbox_live.ex:272-290`

The handler doesn't guard against the current status:
```elixir
def handle_event("send_to_erp", _, socket) do
  case socket.assigns.active_order do
    nil -> {:noreply, socket}
    order ->
      case OrderFlow.mark_sent_to_erp(order) do
        {:ok, updated} -> ... put_flash(:info, "Order ##{...} sent to NeuroniERP as ...")
```

The button is hidden on `status == "sent_to_erp"`, but the flash window is open between click → handler → re-render. A nervous-demo double-click fires the handler twice → two flash messages, both saying "Order #X sent". `mark_sent_to_erp` itself is idempotent (DB-wise), but the audience sees two toasts. Demo-visible.

**Fix:** add a status guard at the top of the handler:
```elixir
case socket.assigns.active_order do
  %{status: "sent_to_erp"} -> {:noreply, socket}
  nil -> {:noreply, socket}
  order -> ...
end
```

## MEDIUM

### MED-A: Distinct-demos query in audit log still pulls every row

**File:** `lib/showcase_web/live/admin/audit_log_live.ex:36-42`

MED-02 from the prior pass pushed the *entries* query to the DB with `:list_recent`, but the sibling `distinct_demos/0` still does:
```elixir
AuditLog |> Ash.read!() |> Enum.map(& &1.demo) |> Enum.uniq() |> Enum.sort()
```

For a localhost demo this is fine (handful of rows). The fix to MED-02 explicitly motivates "DB-side filter + sort + limit. The Ash.read! → Enum.filter pattern in audit_log_live.ex pulled every row over the wire" — but the comment under-promises and over-claims: the `distinct_demos` path is still the original pattern.

**Fix:** add an Ash action `:distinct_demos` that does `SELECT DISTINCT demo` server-side. Won't affect demo day, but the comment promises something that isn't there.

### MED-B: `clear_uploads/0` runs OUTSIDE the seed transaction

**Files:**
- `lib/showcase/planogram/seed.ex:37-44` (`clear_uploads()` then `Repo.transaction`)
- `lib/showcase/restaurant_compliance/seed.ex:46-51` (same shape)

If the seed transaction fails (DB hiccup, FK constraint, anything), files in `priv/static/uploads/planogram` and `priv/static/uploads/restaurant_compliance` are already gone but the rows in DB pointing at them are NOT rolled back — Reset multi only rolls back DB writes. Worse: in a multi-demo Reset, an EARLIER seeder's `clear_uploads` can succeed and a LATER seeder's transaction can fail — file deletes are unconditional.

The user explicitly flagged this. It's not a demo-day blocker (the seeds are reliable for now) but it's a real ordering bug.

**Fix:** swap to `Repo.transaction(fn -> clear_uploads(); upsert... end)` so the file ops are inside the same atomic block (Postgres won't roll back filesystem ops, but at least the file deletion only runs after we're sure the inserts will go through — i.e., move it to right before the `seed_system_prompts()` call after a successful transaction).

### MED-C: Pre-existing `usage` JSONB rows render mock cost as "live"

**Files:**
- `lib/showcase_web/live/planogram/task_detail_live.ex:52`
- `lib/showcase_web/live/restaurant_compliance/inspection_detail_live.ex:50-51`

```elixir
usage_source = if task.usage, do: Map.get(task.usage, "source", "live"), else: "live"
```

The default-on-missing for `"source"` is `"live"`. For ANY row written before the HI-01 fix (the source key didn't exist then), the badge renders the scripted cost as a real Claude cost. For Planogram, all seeded scenarios cost 1.62-2.26¢ — the audience sees "≈ 2.26¢" labelled as live.

In practice the boss will run `mix ecto.reset` before the demo, which clears + reseeds — but the reseeded tasks have `usage: %{}` (empty map, no source), so completed runs during the demo would also default to `"live"` … wait — no, the VisionPipeline at `vision_pipeline.ex:132` always writes `"source" => source` on the new `complete` row. So new completions are fine. Stale completions from a previous run would be wrong — `ecto.reset` clears them. Not a demo-day issue if the boss is disciplined.

**Fix (optional):** default to `"mock"` not `"live"`. The scripted path is the dominant one in this codebase — `"live"` is the unusual case (Manager-authored tasks).

### MED-D: `delete_message` transaction handles raise badly

**File:** `lib/showcase/order_flow.ex:113-132`

```elixir
Repo.transaction(fn ->
  from(o in Order, where: o.synthetic_message_id == ^msg.id)
  |> Repo.update_all(set: [synthetic_message_id: nil])
  Repo.delete!(msg)   # <-- raises on failure, does NOT return {:error, ...}
end)
|> case do
  {:ok, _} -> ...
  {:error, _} = err -> err
end
```

If `Repo.delete!` raises (DB constraint, missing record, connection blip), the function doesn't fall into the `{:error, _}` clause — the exception propagates out and crashes the LV process. `Repo.transaction/1` does NOT catch arbitrary exceptions and convert them to `{:error, ...}`.

Note also: the `update_all` is redundant — `on_delete: :nilify_all` on the FK (see `priv/repo/migrations/...synthetic_messages...`) already handles cascade. Belt-and-suspenders, fine.

**Fix:** use `Repo.delete(msg)` (returns `{:ok | :error, ...}`) and pattern-match inside the transaction:
```elixir
Repo.transaction(fn ->
  Repo.update_all(...)
  case Repo.delete(msg) do
    {:ok, _} -> :ok
    {:error, cs} -> Repo.rollback(cs)
  end
end)
```

## LOW

### LO-A: `scripted_response_for/1` called twice per analysis

**Files:**
- `lib/showcase/planogram/vision_pipeline.ex:81-82`
- `lib/showcase/restaurant_compliance/vision_pipeline.ex:81-82`

```elixir
cond do
  live_impl?() and match?({:ok, _}, MockPrompts.scripted_response_for(task.scenario)) ->
    {:ok, response} = MockPrompts.scripted_response_for(task.scenario)  # ← duplicate
```

Pure function, deterministic, but it `Jason.encode!`s a moderately large map on each call. ~negligible CPU, but smells. The Erlang idiom is `with`:
```elixir
case MockPrompts.scripted_response_for(task.scenario) do
  {:ok, response} when live -> {:ok, response, "mock"}
  _ -> call_real()
end
```

Not a race because the function is pure. Not blocking.

### LO-B: Stale `NeedsHumanBadge` reference in module doc

**File:** `lib/showcase/common/needs_human.ex:6`

The doc references `NeedsHumanBadge` component, which was deleted in the LOW-tier cleanup pass. Cosmetic; broken docstring promise.

### LO-C: `audit_log_indexes` migration missing trailing `inserted_at`

**File:** `priv/repo/migrations/20260607225525_audit_log_indexes.exs:9`

```elixir
create_if_not_exists index(:common_audit_logs, [:demo, :entity_type, :entity_id])
```

The `:for_entity` Ash action does `where: demo == ^... and entity_type == ^... and entity_id == ^...`, **then** `sort: [inserted_at: :desc]`. Without `inserted_at` in the index, Postgres does an extra sort step. Won't matter at demo scale (few rows); will matter if the boss ships this to a real customer for a pilot.

**Fix:** add `inserted_at` to the trailing column of the second index.

### LO-D: `compose_changeset` silently drops attachments on string-keyed attrs

**File:** `lib/showcase/order_flow/schemas/synthetic_message.ex:56`

```elixir
|> put_change(:attachment_paths, Map.get(attrs, :attachment_paths, []))
```

The comment correctly notes this is intentional ("LiveView passes the consumed-upload paths via the dedicated `attachment_paths` atom key") — but `compose_changeset/2` is a public function. Any future caller passing string-keyed attrs gets silently dropped attachments. Not a current bug; latent.

**Fix:** accept both, or rename the function to `compose_changeset_from_lv/2` to make the contract louder. Not worth fixing tomorrow.

### LO-E: `Mock.register` ordering in `Application.start/2` for dev is dead code

**File:** `lib/showcase/application.ex:31-38`

The conditional checks `Application.get_env(:showcase, :anthropic_client_impl) == Mock`. In dev this is `Live` (config.exs:85), so the registration block is **never executed in dev**. It's only useful in test. The branch is correct, but the comment "When the configured AnthropicClient impl is the Mock (tests + dev with no API key)…" implies the dev-no-api-key case is covered, which it isn't (the impl is still `Live`, it just authenticates with `""` and fails on the first real call).

Cosmetic. The branch *does* work for tests, which is what matters.

---

## Verified clean (no regression found)

1. **BL-01 `:unknown` atom round-trip** — `safe_atom` returns `:unknown`, `Atom.to_string(:unknown)` → `"unknown"` → JSONB → `String.to_existing_atom("unknown")` succeeds because `:unknown` is referenced in `safe_atom/1` itself. No corruption.
2. **HI-02 `Mock.reset()` removal from `MockPrompts.register_all/0`** — only callsite that relied on reset semantics is `mock_prompts_test.exs:9`, which now explicitly calls `Mock.reset()` first. All other call sites are additive overwrites.
3. **MED-03 mock registration in `Application.start`** — verified the dev demo flow doesn't depend on it (Live impl uses `MockPrompts.scripted_response_for/1` directly, bypassing the ETS table). Test files all self-register in their own setup blocks. The boot-time registration is dead code in dev but harmless.
4. **MED-04 `delete_message` transaction** — wrapping is correct (FK is `:nilify_all` so the `update_all` is redundant but not harmful). See MED-D above for the unrelated raise-handling concern.
5. **MED-07 `compose_changeset` attachment_paths via `put_change`** — atom key path works, see LO-D for the unhandled string-key edge case.
6. **MED-08 `get/3` for thresholds drops atom fallback** — all callers pass string-keyed maps (LV form params + Postgres JSONB). No regression.
7. **HI-01 scripted_response_for branching** — race-safe (pure function). See LO-A for the style smell.
8. **Send-to-ERP idempotency** — `mark_sent_to_erp` is idempotent at the DB layer; the UI hides the button after status flips. See HI-B for the double-flash UX concern.
9. **CLAUDE.md rule compliance** — no new `Repo`, clock reads, or `HTTPoison` calls in `impl/` modules. No direct Anthropix calls outside `AnthropicClient.Live`. No `Jason.decode!` on response text (everything goes through `ResilientJSONParser`). No cross-demo joins.
10. **`self_improving_loop_test.exs` rewrite** — verifies the same behavior (cascade goes claude_fallback → correction adds alias → re-run hits client_alias). The new "the brown handles" / `K1001-11-n03` setup is equivalent in coverage to the old "gizmo things" / `GDG-001` setup.
11. **`OrderDetailLive` deletion** — fully absorbed into the InboxLive 3-pane. Route deleted, tests deleted, no leftover references. Clean.
12. **`ResetButton`, `CascadeMatrix`, `PipelineStages`, `NeedsHumanBadge`, `AuditTrail` component deletions** — no leftover references in lib/ or test/ (one stale docstring caught above as LO-B).

---

## Demo-day breakability check (concrete failure modes)

| Risk | Status | Notes |
|---|---|---|
| Boss double-clicks "Send to ERP" | **Minor UX wart** | HI-B above. Two flashes, idempotent state. |
| `mix ecto.setup` ordering Application.start vs seeds | **Safe** | Seeds never depend on Mock ETS (scripted text comes from `MockPrompts.scripted_response_for/1` directly). |
| Reset clears uploads then DB fails | **Latent** | MED-B above. Won't trigger without a separate DB problem. |
| Cost badge labels mock as "live" | **Safe** | New rows write `"source"`; reseed clears stale rows. |
| `:unknown` atom from Claude crashes | **Safe** | Round-trips through JSON cleanly. |
| Mock race in tests | **Won't affect demo** | HI-A is a CI flake risk, not a runtime risk. |
| RC has 0 tests | **Accepted risk** | Author rolled with manual smoke. New code path not covered. |
| Composed message tries Claude with no key set | **Author's call** | Will fail with auth error — but the demo flow uses seeded `composed: false` messages. Composed flow is only triggered if boss clicks "Write an email" mid-pitch. |

---

_Reviewed: 2026-06-08_
_Reviewer: Claude (adversarial second-pass)_
_Branch: chore/medium-low-cleanup_
_Test status assumed: 1 property, 299 tests, 0 failures._
