# Plan Review: 61-fix-crash-on-disconnect-when-session-already-stopped

**Files Reviewed:** 1 plan + targeted source (`example/lib/providers/active_device_provider.dart`, `lib/src/api/device.dart`, `example/lib/main.dart`, `example/lib/screens/device_screen.dart`)
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture:** No relevant boundary or layering issue. The change stays inside the example app's provider layer; it does not touch the public plugin API (`lib/src/api/`). OK.
- **Rules:** No `.ai-factory/RULES.md` present. WARN (optional file, not blocking).
- **Roadmap:** No explicit milestone linkage in the plan body. Since this is a crash fix, mentioning the linked roadmap entry (if any exists for "fix on disconnect" or task 61) would help orchestrator continuity. WARN.

## Verification of Plan Assumptions

- `Device.isStarted` is exposed: confirmed at `lib/src/api/device.dart:302` (`bool get isStarted => _started`).
- `_started` is reset to `false` by `stop()` (line 215), `disconnect()` (188), `dispose()` (230), and by the connection-state listener when the device transitions to `disconnected` (line 142). So `!isStarted` reliably gates out the double-`stop` path described in the context, including the racy auto-disconnect case that originally triggered the SIGABRT.
- `dispose()` is idempotent: `if (_disposed) return;` at line 223. ✅
- `disconnect()` followed by `dispose()` calls the native `disconnect` method twice, but the source comment at line 226 explicitly states "Idempotent on the native side even if already disconnected." The plan's claim that `disconnect()` and `dispose()` are safe to leave alone is consistent with that comment. ✅
- Target call sites in `example/lib/providers/active_device_provider.dart`:
  - Task 1 target — line 57, inside `disconnectAndDispose()`. Confirmed.
  - Task 2 target — line 28, inside `createAndConnect()` cleanup block. Confirmed.

The two file paths, line numbers, and surrounding `try { ... } catch (_) {}` structure described in the plan match the actual source exactly. The fix as specified is correct for both sites.

## Critical Issues

None — the proposed change is mechanically sound and addresses the root cause for the scoped file.

## Gaps / Missing Steps

**Missed call site: `example/lib/main.dart:42`**

`_AppState._cleanupAndDispose()` performs the same unconditional `device.stop()` → `disconnect()` → `dispose()` sequence the plan is fixing in `active_device_provider.dart`:

```dart
// example/lib/main.dart:38–52
Future<void> _cleanupAndDispose() async {
  final device = _container.read(activeDeviceProvider);
  if (device != null) {
    try {
      await device.stop();          // ← same unguarded stop()
    } catch (_) {}
    try {
      await device.disconnect();
    } catch (_) {}
    try {
      await device.dispose();
    } catch (_) {}
  }
  _container.dispose();
}
```

Reachable crash path:
1. User connects → `start()` (`_started = true`).
2. User taps the in-app Stop button (`device_screen.dart:133`) → native stop succeeds, `_started = false`.
3. User backgrounds/closes the app → `_cleanupAndDispose()` fires → `device.stop()` called on an already-stopped session → SIGABRT in `libCapsuleClient.so` (the very crash this plan is fixing).

Other reach: any time the device auto-disconnects (line 142 sets `_started = false` from the connection-state listener) before the user closes the app, app-shutdown cleanup hits the same crash.

**Recommended addition:** add a Task 3 that applies the identical `if (device.isStarted)` guard around the `await device.stop();` in `_cleanupAndDispose()`. Same pattern, same rationale — leaving it unguarded means the SIGABRT still ships for one realistic shutdown path. Without it, the plan only fixes the explicit "Disconnect" button path and leaves the app-shutdown path broken.

`device_screen.dart:133` (the Stop button itself) does not need a guard — that handler is the thing that transitions `_started` from true to false, and the UI presumably gates the button on `isStarted`. Worth a quick sanity check during implementation, but not a missing task.

## Minor Notes

- The plan's `Settings: Logging: minimal` paired with `try { ... } catch (_) {}` means a recurrence of the crash (e.g., a different SDK precondition) would be swallowed silently. Consider at least one `log(...)` in the catch branch in case future similar bugs need to be diagnosed from user devices. Not blocking.
- `Testing: no` is reasonable given the example app context, but a single unit test asserting `disconnectAndDispose()` does not call `device.stop()` when `device.isStarted == false` would be cheap insurance against regression. Optional.

## Positive Notes

- Plan correctly preserves the surrounding `try/catch` so any unrelated race-condition error is still swallowed (`disconnect()` after auto-disconnect, etc.).
- Plan correctly identifies that `disconnect()` and `dispose()` are idempotent on the native side and need no guard — confirmed against the device.dart source comment.
- Line numbers, file path, and code structure described in the plan match the source exactly — no drift.
- Scope is appropriately narrow: a 4-line, 2-call-site behavioral fix, no architectural churn.

## Verdict

The plan is correct for the call sites it covers, but it misses `example/lib/main.dart:42`, which is the same anti-pattern in the app-shutdown teardown path and is reachable from a routine "Stop, then close app" user flow. Add one task to guard that call site before promoting the plan to implementation.
