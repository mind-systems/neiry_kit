# Plan Review: Guard connect() against a stale device

**Plan:** `.ai-factory/plans/82-guard-connect-against-a-stale-device.md`
**Target:** `example/lib/services/neiry_service.dart`
**Risk Level:** 🟢 Low

## Code Review Summary

**Files Reviewed:** 1 plan + target source + spec note 35 + ROADMAP milestone 130

The plan is a small, well-scoped, pure-Dart fix. Every claim it makes about the
codebase was verified against the current source and the spec note, and they all hold.

### Context Gates

- **Architecture (`ARCHITECTURE.md` present):** WARN — none. The change lives in the
  example app's service layer (`example/lib/services/`) and introduces no new
  cross-boundary dependency. It reuses the existing `disconnect()` teardown. No
  architectural concern.
- **Rules (`RULES.md`):** absent — gate skipped (WARN, non-blocking).
- **Roadmap (`ROADMAP.md` present):** PASS — milestone 130 ("Guard connect() against a
  stale device") matches the plan exactly, including the `Fatal signal 64` / `0xebadde09`
  symptom and the `clC… module already exists` cause. Linkage is clear.
- **Skill-context (`aif-review/SKILL.md`):** absent — no project overrides to apply.

### Verified Assumptions (all correct)

- **File path** `example/lib/services/neiry_service.dart` — correct.
- **Insertion point** "≈ lines 120–125, after `_checkNotDisposed()` / `if (_connecting)` /
  `if (isConnected)` and before `_connecting = true`" — matches the source (guards at
  120–123, `_connecting = true` at 125).
- **`disconnect()` is idempotent and returns early on `_device == null`** — confirmed
  (line 260).
- **`disconnect()` releases classifiers + native modules + device handle and nulls
  `_device`** — confirmed (steps 3–5, `_device = null` at line 349).
- **`disconnect()` recreates the locator when `!_disposed`** — confirmed (lines 359–366).
  Note that `connect()` reads `_locator` as a field at call time (line 130), so after the
  teardown it correctly picks up the freshly recreated locator. This is exactly the
  intended behavior and avoids reusing the stale cached `clCDevice`.
- **`isConnected == false` after a silent drop while `_device != null`** — confirmed by
  the getter (`_device?.isConnected ?? false`, line 87) and corroborated by note 35
  (log01: `_device: set isConnected: false`). The existing `if (isConnected) throw` guard
  correctly does not fire, and the new teardown handles the stale handle.
- **Log convention** `nlog(..., name: 'neiry_kit')` — matches every existing call site.
- **Plan faithfully matches spec note 35** (`.ai-factory/notes/35-...`), including the
  exact log string and placement.

### Critical Issues

None. The plan does not require migrations, native changes, or API-surface changes.

### Observations (non-blocking)

1. **Re-entrancy window during the teardown `await` (minor).** The plan places
   `await disconnect()` *before* `_connecting = true`. The plan's stated rationale —
   "Re-entrancy is safe… `_connecting` is still false" — is the very thing that leaves the
   `if (_connecting) throw` guard open across the async teardown. If `connect()` were
   invoked a second time while the first call is awaiting `disconnect()`, the second call
   would pass all guards and also begin a teardown/connect. This is a theoretical concern
   only: the example app drives `connect()` from a UI button typically disabled by device
   state, and the spec (note 35, line 41) deliberately accepts this placement. If you want
   to close the window with no downside, set `_connecting = true` first and move the
   teardown to the top of the existing `try` block (the `finally` already resets the flag,
   and `disconnect()` never reads `_connecting`). Optional — not required for correctness
   of the targeted crash fix.

2. **`disconnect()` emits a synthetic `NeiryConnectionState.disconnected`** (line 267)
   when tearing down the stale device. This is harmless and arguably desirable (it nudges
   any consumer still showing "connected" back to disconnected), but worth being aware of:
   the reconnect path will briefly push a `disconnected` event before the new session's
   events arrive. No action needed.

### Positive Notes

- Reuses the already-hardened, idempotent 5-step `disconnect()` rather than introducing a
  parallel teardown path — the right call given the crash history (milestones 110, 106).
- Correctly preserves the `if (isConnected) throw` guard so a genuinely-live double-tap
  still throws rather than silently reconnecting.
- Single log line, minimal-logging setting respected; no test/doc scope creep.
- Verification steps are concrete and reproduce the original crash path.

The plan is solid and ready to implement.

PLAN_REVIEW_PASS
