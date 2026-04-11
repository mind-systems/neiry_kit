# Plan Review: Device Tab (Round 2)

**Plan file:** `.ai-factory/plans/41-device-tab.md`
**Files Reviewed:** 8 (plan + 7 codebase files)
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** WARN — no violations. Plan stays within `example/` boundary, imports from `lib/` public API via `neiry_kit` barrel only. Provider and screen file paths match the architecture's `example/lib/providers/` and `example/lib/screens/` layout.
- **RULES.md:** not present — WARN, skipped.
- **ROADMAP.md:** plan implements the "Device tab" milestone. All patterns (FutureProvider.family, NotifierProvider, StreamProvider, StateProvider, composite Provider, async disposal) match the roadmap spec and explore notes at `.ai-factory/notes/13-explore-example-device-providers.md`.

## Previous Review Status

All 4 findings from review-1 were already addressed in the plan text:
1. ~~Double-dispose of DeviceLocator~~ — Task 6 explicitly says "Do **not** dispose `DeviceLocator` here" and explains why. No issue.
2. ~~`unsupportedConnection` not handled~~ — Task 3 explicitly states "if connection is **not** `NeiryConnectionState.connected` → `idle` (this covers both `disconnected` and `unsupportedConnection`)". No issue.
3. ~~Nullable vs non-nullable locator confusion~~ — Tasks 1 and 2 both state "(non-nullable — no null check needed)". No issue.
4. ~~ConsumerStatefulWidget~~ — Task 6 explicitly says "(not `ConsumerStatefulWidget` — the cleanup reads from `_container` directly and never uses `ref`)". No issue.

## Critical Issues

### 1. Native device handle leaks when `connect()` fails inside `createAndConnect`

**Task 2** describes `createAndConnect` flow as: call `createDevice(serial)` → call `device.connect()` → set `state = device`.

If `connect()` throws (e.g., BLE timeout, unsupported device), the `Device` instance was already created by `createDevice()` — a native handle was allocated on the platform side via `DeviceLocatorMethods.createDevice`. Since `state` was never set to the new device, no code path ever disposes it. The native handle leaks.

**Task 5** says "If connect fails, reset `activeDeviceProvider` to null" — but `state` is already `null` at that point (never set), so this is a no-op and doesn't fix the leak.

`Device.dispose()` is idempotent (`if (_disposed) return;` at `device.dart:209`), so calling it in the error path is safe.

**Fix:** In `createAndConnect`, if `connect()` throws, call `device.dispose()` before rethrowing:
```dart
Future<void> createAndConnect(String serial, {bool bipolarChannels = false}) async {
  // ... old device cleanup ...
  final locator = ref.read(deviceLocatorProvider);
  final device = await locator.createDevice(serial);
  try {
    await device.connect(bipolarChannels: bipolarChannels);
  } catch (e) {
    await device.dispose(); // release the native handle
    rethrow;
  }
  state = device;
}
```

Update Task 5 to remove the incorrect "reset `activeDeviceProvider` to null" instruction for connect failure — `device.dispose()` in the method itself handles cleanup. The catch in the UI layer only needs to show the SnackBar.

## Positive Notes

- Plan correctly models the SDK's single-emission `requestDevices()` as `FutureProvider.family` with `ref.invalidate()` for re-scan — idiomatic and efficient.
- One-device-at-a-time enforcement in `ActiveDeviceNotifier` correctly mirrors the EventChannel singleton constraint documented in `Device` class (`device.dart:17–23`).
- The composite `deviceUiStateProvider` cleanly separates "connection state" from "started flag" and derives button enabled state without widget-level logic.
- Async disposal strategy in Task 6 is well-designed: explicit ordered cleanup before `_container.dispose()`, avoids double-dispose of locator, and the `ref.onDispose` fire-and-forget in Task 2 serves as a last-resort safety net.
- All type names, method signatures, and stream shapes in the plan match the actual `DeviceLocator` and `Device` API as implemented in `lib/src/api/`.

PLAN_REVIEW_PASS
