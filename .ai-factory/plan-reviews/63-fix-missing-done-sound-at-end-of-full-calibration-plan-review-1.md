# Plan Review: 63-fix-missing-done-sound-at-end-of-full-calibration (iteration 1)

## Summary

**Risk Level:** 🟢 Low

The plan correctly identifies a real microtask-ordering race in `CalibrationNotifier`
and proposes a fix that mirrors an existing precedent in the same file
(`Future.microtask(() => _aborted = false)` on line 128). File paths, line numbers,
and code references all match the actual codebase. The change is small, surgical,
and architecturally consistent.

One sub-claim in the plan's stated rationale is overstated (see Task 1 below),
but the proposed change itself is harmless and the rest of the plan is sound.

### Context Gates
- **Architecture (`ARCHITECTURE.md`):** Plan touches only `example/lib/` (the
  example app, not the public `lib/src/...` plugin surface). No boundary or
  layering concern. ✓
- **Rules:** No `.ai-factory/RULES.md` present. No project rule conflicts found.
- **Roadmap:** Milestone 63 follows from milestone 62 (the "done cue" feature).
  Linkage explicit in the Context section. ✓

## Verified Against Codebase

| Claim in plan | File | Verified |
|---|---|---|
| `_CalibrationCard extends ConsumerWidget` | `example/lib/screens/calibration_screen.dart:39` | ✓ |
| `ref.listen(calibrationTimerProvider, …)` | `calibration_screen.dart:44` | ✓ |
| `ref.listen<AsyncValue<IndividualNfbData?>>(calibrationProvider, …)` | `calibration_screen.dart:51` | ✓ |
| `_running = false;` after `state = await AsyncValue.guard(...)` in `startFull` (line 88) | `example/lib/providers/calibration_provider.dart:88` | ✓ |
| `_running = false;` in `startQuick` (line 108) | `calibration_provider.dart:108` | ✓ |
| `_running` doc comment (lines 27–33) | `calibration_provider.dart:27-33` | ✓ |
| Precedent `Future.microtask(() => _aborted = false);` in `abort()` (line 128) | `calibration_provider.dart:128` | ✓ |
| `_writeToSharedProvider()` and `if (_aborted) return;` ordering in `startFull` | `calibration_provider.dart:90-91` | ✓ |
| `isRunning` getter and `_running` field | `calibration_provider.dart:33-36` | ✓ |

## Race Condition Analysis

The microtask ordering is the genuine root cause and the fix is correct:

1. `state = await AsyncValue.guard(...)` assigns the terminal state and Riverpod
   schedules listener notification as a **microtask**.
2. The current synchronous `_running = false;` on the next line runs **before**
   the microtask queue drains, so by the time the listener callback fires,
   `notifier.isRunning` reads `false` and the `if (!notifier.isRunning) return;`
   guard short-circuits before `playDone()` is reached.
3. `Future.microtask(() => _running = false)` enqueues the assignment **after**
   the listener-notification microtask (FIFO microtask ordering), so the listener
   sees `isRunning == true` and proceeds to `playDone()` / `playError()`.

Interaction with `abort()`:
- After Task 2, when `abort()` errors the completer, `startFull` resumes,
  state transitions to error (listener observes `isAborting == true`, skips cue ✓),
  `Future.microtask(() => _running = false)` is queued, then `if (_aborted) return;`
  returns. `abort()` later assigns `state = AsyncValue.data(...)`. Both `_running`
  and `_aborted` microtasks fire after their respective listener notifications.
  No new race introduced. ✓

## Findings

### Minor — Task 1 rationale is overstated (non-blocking)

The plan claims: *"listeners re-register on every rebuild and miss the
loading → data transition"*.

In modern Riverpod, `ref.listen` inside `ConsumerWidget.build()` is officially
supported. Listeners are tracked per call site on the `ProviderElement`; on
rebuild the registration is updated, not duplicated, and the `prev`/`next`
pair is preserved across rebuilds. Riverpod schedules the listener notification
microtask **before** marking dependents for rebuild, so a missed transition due
to "re-registration" is not the actual failure mode here.

The real failure mode is the synchronous `_running = false;` race addressed by
Tasks 2 and 3. Task 1's conversion to `ConsumerStatefulWidget` is **harmless and
arguably good hygiene** (clearer lifecycle, friendlier to `ref.listenManual` if
ever added), but is not load-bearing for the fix.

**Recommendation:** Either keep Task 1 (defensive cleanup — fine) or drop it and
ship just Tasks 2–4. If kept, consider softening the doc-comment justification
in the plan/PR description so it doesn't enshrine an incorrect mental model of
Riverpod's listener semantics.

### Minor — Doc comment update (Task 4) should also note `Future.microtask`

The current comment on lines 27–33 says the flag is "cleared synchronously on
the line after `state = await AsyncValue.guard(...)`". Task 4 says to update
this, which is correct. Suggest the new wording explicitly call out the
*reason* — i.e., "deferred via `Future.microtask` so the Riverpod
listener-notification microtask fires first" — so a future reader doesn't
revert it back to a synchronous assignment on cleanup grounds.

### Positive Notes

- Plan correctly identifies that **both** `startFull` and `startQuick` have the
  same race (Tasks 2 and 3) — the bug is symmetric and the plan treats it so.
- Mirrors the established `_aborted = false` microtask precedent already in the
  same file (line 128). Consistency with existing patterns is good.
- Correctly preserves the existing `if (_aborted) return;` guard and
  `_writeToSharedProvider()` ordering in `startFull` — neither depends on
  `_running` so reordering is safe.
- Settings (`Testing: no`, `Logging: minimal`, `Docs: no`) are appropriate for
  a 4-line behavioral fix.
- Task dependencies are correctly chained.
- No security, migration, performance, or API-misuse concerns.

## Verdict

The plan is solid. The fix targets the actual root cause (microtask ordering)
and the line references all check out. Task 1's stated rationale is the only
real wart, and the change itself is benign. No blockers.

PLAN_REVIEW_PASS
