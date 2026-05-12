# Plan Review: 61-fix-crash-on-disconnect-when-session-already-stopped (v2)

**Files Reviewed:** plan v2 + targeted source (`example/lib/providers/active_device_provider.dart`, `example/lib/main.dart`, `example/lib/screens/device_screen.dart`, `lib/src/api/device.dart`)
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture:** No boundary issue. The change stays inside the example app's provider/widget layer and does not touch the public plugin API in `lib/src/api/`. OK.
- **Rules:** No `.ai-factory/RULES.md` present in this repo. WARN (optional file, non-blocking).
- **Roadmap:** No explicit linkage to a ROADMAP.md milestone in the plan body. Cosmetic — this is a crash fix scoped to the example app. WARN.

## Verification of Plan Assumptions

- `Device.isStarted` exists and is the right gate: `lib/src/api/device.dart:302` (`bool get isStarted => _started`).
- `_started` is reset to `false` in all relevant transitions: `disconnect()` line 188, `stop()` line 215, `dispose()` line 230, and the connection-state listener on auto-disconnect line 142. So `if (device.isStarted)` correctly skips the double-stop in every reachable case, including the racy auto-disconnect path that produced the original SIGABRT.
- `dispose()` is idempotent (`if (_disposed) return;` line 223). The native `disconnect` is invoked again from `dispose()` after a manual `disconnect()`, but the source comment at line 226 explicitly states it is idempotent on the native side. The plan's choice to leave `disconnect()` and `dispose()` unguarded is consistent.
- Target call sites verified line-for-line:
  - Task 1 — `example/lib/providers/active_device_provider.dart:57` inside `disconnectAndDispose()`. Confirmed.
  - Task 2 — `example/lib/providers/active_device_provider.dart:28` inside `createAndConnect()` cleanup. Confirmed.
  - Task 3 — `example/lib/main.dart:42` inside `_AppState._cleanupAndDispose()`. Confirmed.

The "stop, then close app" path that review-1 flagged is addressed by Task 3.

## Diff vs. v1

v2 adds Task 3 covering `main.dart:_cleanupAndDispose()` — the exact gap identified in plan-review-1. All three reachable unconditional `device.stop()` sites in the example app are now covered.

## Other Call Sites — Sanity Check

Audit of remaining `device.stop()` usages in the example app:

- `example/lib/screens/device_screen.dart:133` — `_stop()` button handler. This is the call that transitions `_started` from `true` → `false`; it is gated by UI state (Stop button only enabled when the device is started). Not a regression site — no guard needed, consistent with review-1's note.

No other unguarded `device.stop()` call sites exist in the example app.

## Critical Issues

None.

## Gaps / Missing Steps

None. The three sites covered by Tasks 1–3 are the complete set of unguarded `device.stop()` call sites reachable from the example app's lifecycle.

## Minor Notes

- `Settings: Logging: minimal` plus `try { ... } catch (_) {}` means a future, unrelated SDK precondition failure inside `stop()` will be swallowed silently in all three sites. Not blocking — matches the existing pattern in the file — but a single `log(...)` in the catch branch would help diagnose recurrences from user devices. Optional.
- `Testing: no` is acceptable for this surgical example-app fix. A trivial unit test asserting `disconnectAndDispose()` does not invoke the underlying stop channel call when `!isStarted` would be cheap regression insurance but is not required.

## Positive Notes

- Plan v2 fully addresses the review-1 feedback (Task 3 added) without expanding scope.
- Plan correctly preserves the surrounding `try/catch` wrappers so unrelated transient errors (e.g., disconnect-after-auto-disconnect) remain swallowed as before.
- File paths and line numbers in all three tasks match the current source exactly — no drift.
- Scope remains appropriately narrow: three two-line behavioral changes, single shared pattern, no architectural churn.
- Task 3's rationale text explicitly describes the reachable crash path ("user taps Stop, then closes the app"), which makes the intent unambiguous for the implementer.

## Verdict

The plan is mechanically sound, matches the source, and now covers every reachable double-stop site in the example app. Ready for implementation.

PLAN_REVIEW_PASS
