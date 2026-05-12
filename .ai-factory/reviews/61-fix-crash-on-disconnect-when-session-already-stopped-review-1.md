# Code Review: 61-fix-crash-on-disconnect-when-session-already-stopped

**Files Reviewed:**
- `example/lib/providers/active_device_provider.dart` (modified, full read)
- `example/lib/main.dart` (modified, full read)
- `lib/src/api/device.dart` (full surrounding context: lines 1–235, 287–305)

**Risk Level:** 🟢 Low

## Scope of Changes

Three single-line guards added around `device.stop()` calls. Diff is exactly what the plan specified:

1. `example/lib/providers/active_device_provider.dart:28` (inside `createAndConnect` cleanup of an existing device)
2. `example/lib/providers/active_device_provider.dart:57` (inside `disconnectAndDispose`)
3. `example/lib/main.dart:42` (inside `_AppState._cleanupAndDispose`)

Each follows the same pattern: `if (device.isStarted) await device.stop();` inside the existing `try { ... } catch (_) {}` block. `disconnect()` and `dispose()` are left untouched as they are idempotent on the native side.

## Correctness Verification

- **`isStarted` getter is safe post-dispose.** `device.dart:302` defines `bool get isStarted => _started;` with no `_checkNotDisposed()` call. So reading it after a prior `dispose()` does not throw. ✅
- **`_started` is correctly false in every state that should skip `stop()`:**
  - After `stop()` (`device.dart:215`)
  - After `disconnect()` (`device.dart:188`)
  - After `dispose()` (`device.dart:230`)
  - After the native connection-state listener flips to `disconnected` (`device.dart:142`) — this is the auto-disconnect race that produced the original SIGABRT
- **No race window introduced.** The check-then-call is synchronous up to the `await` in `invokeMethod`. The only path that could flip `_started` between the check and the awaited native call is the EventChannel listener on `_connectionStateStream`, which can only fire on a microtask/event-loop tick. The guard executes synchronously before any such tick can deliver. The pre-existing surrounding `try/catch` still swallows any error that does sneak through. ✅
- **`existing.isStarted` in `createAndConnect`:** the previously held device may have already been auto-disconnected; in that case `_started == false`, so we skip `stop()` and proceed straight to `disconnect()` / `dispose()`. Matches the original SIGABRT fix intent. ✅

## Runtime Behavior Audit

- **No new exceptions exposed.** All three sites already wrap `stop()` in `try { ... } catch (_) {}`. The guard reduces the set of cases that even reach `stop()` and does not introduce a new error surface.
- **No state leak.** The only state mutated by `stop()` (`_started = false`) is already `false` in the skipped path by definition. Nothing the rest of the cleanup depends on is left in an unexpected state.
- **`_AppState.dispose()` does not `await _cleanupAndDispose()`** — this is pre-existing behavior, not introduced by this patch. The State will return from `dispose()` while the async cleanup is still in flight. Not in scope for this fix.
- **`device_screen.dart:133` (Stop button handler)** — confirmed by plan-review-2 as the legitimate `true → false` transition site for `_started`. Not modified, correctly so.

## Type / Compile Concerns

- The added expression `if (device.isStarted) await device.stop();` is a valid Dart `if`-statement form (no braces required for a single statement). The `await` is still inside the enclosing `async` function. No type issues — `device.stop()` returns `Future<bool>`, the result was already being discarded.

## No Other Unguarded `device.stop()` Sites

Plan-review-2 already verified the example app has no further unguarded sites; the diff confirms only the three intended files changed. The library code under `lib/src/api/` is untouched, preserving the public API.

## Minor Notes (non-blocking)

- The `try { ... } catch (_) {}` blocks silently swallow any future SDK precondition failures from `stop()`/`disconnect()`/`dispose()`. A single `log(...)` in the catch would aid post-mortem debugging if a similar bug recurs. Consistent with the plan's "Logging: minimal" setting and the existing pattern in the file — not a regression introduced here.
- No regression test was added (plan explicitly set `Testing: no`), so a future change that re-introduces the unguarded `stop()` would not be caught by CI. Acceptable for an example-app fix.

## Verdict

The fix is mechanically correct, matches the plan exactly, and closes all three reachable double-stop crash paths in the example app. No bugs, no security issues, no type/runtime concerns introduced.

REVIEW_PASS
