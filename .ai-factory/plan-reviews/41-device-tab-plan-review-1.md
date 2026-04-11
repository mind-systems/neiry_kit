# Plan Review: Device Tab

**Plan file:** `.ai-factory/plans/41-device-tab.md`
**Files Reviewed:** 10 (plan + 9 codebase files)
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** WARN — plan aligns with the architecture's dependency rules (`example/` depends on `lib/` public API only) and the `example/providers/` + `example/screens/` folder structure. No violations.
- **RULES.md:** not present (no file) — WARN, skipped.
- **ROADMAP.md:** plan matches the "Device tab" milestone description exactly. All provider patterns (FutureProvider.family, NotifierProvider, StreamProvider, StateProvider, composite Provider) and the async disposal strategy are consistent with the roadmap spec.

## Critical Issues

### 1. Double-dispose of DeviceLocator causes runtime crash on app shutdown

**Task 6** instructs: "read `deviceLocatorProvider` and call `dispose()`" inside `_performCleanup()`. Then `_container.dispose()` is called, which triggers the existing `ref.onDispose(() => locator.dispose())` in `device_locator_provider.dart` (line 8).

`DeviceLocator.dispose()` is **not idempotent** — it calls `_checkNotDisposed()` first and throws `StateError('DeviceLocator has been disposed')` on the second call (`device_locator.dart`, line 216). This will crash during app teardown.

By contrast, `Device.dispose()` **is** idempotent (`if (_disposed) return;` at `device.dart`, line 209), so double-disposing the device is safe.

**Fix:** Remove the locator disposal line from `_performCleanup()`. Let `ref.onDispose` handle it when `_container.dispose()` runs. The explicit async cleanup should only cover the active device (stop → disconnect → dispose), which is the part that actually needs ordered async teardown. The locator's single `dispose()` call works fine as fire-and-forget from `ref.onDispose`.

Updated `_performCleanup()` should be:
```dart
Future<void> _performCleanup() async {
  final device = _container.read(activeDeviceProvider);
  if (device != null) {
    try {
      await device.stop();
      await device.disconnect();
      await device.dispose();
    } catch (_) {}
  }
  // Do NOT dispose locator here — ref.onDispose handles it
  // when _container.dispose() runs below.
}
```

## Suggestions

### 2. Handle `NeiryConnectionState.unsupportedConnection` in composite state

**Task 3** defines `deviceUiStateProvider` logic as: "if connection is `disconnected` → `idle`; if connected and `isStarted` → `started`; if connected and not started → `connected`."

`NeiryConnectionState` has three values: `disconnected`, `connected`, `unsupportedConnection` (`enums.dart`, line 73–92). The current logic only checks for `disconnected` — `unsupportedConnection` falls through to the "connected" branch, which would enable Start/Disconnect buttons for an unusable connection.

**Suggestion:** Treat `unsupportedConnection` as `idle` (same as `disconnected`), or add a fourth `DeviceUiState.error` variant:
```dart
if (conn != NeiryConnectionState.connected) return DeviceUiState.idle;
```

### 3. Explore notes show nullable `DeviceLocator?` but actual provider is non-nullable

The plan says "Follow the existing pattern in `device_locator_provider.dart`" and references explore notes at `.ai-factory/notes/13-explore-example-device-providers.md`. The explore notes show `DeviceLocator?` (nullable) in sample code with null checks (`if (locator == null) throw StateError(...)`). The actual provider is `NotifierProvider<DeviceLocatorNotifier, DeviceLocator>` — non-nullable (line 13–16 of `device_locator_provider.dart`).

The plan's task descriptions don't repeat the null check, which is correct. But an implementer reading the referenced notes literally could add unnecessary null checks or, worse, change the provider type to nullable for consistency with the notes.

**Suggestion:** Add a note to Task 1 or Task 2 clarifying that `deviceLocatorProvider` returns non-nullable `DeviceLocator` — no null guard needed.

### 4. `ConsumerStatefulWidget` is unnecessary for Task 6

Task 6 says to convert `NeiryExampleApp` to `ConsumerStatefulWidget`. The cleanup reads from `_container` directly — it never uses `ref`. A plain `StatefulWidget` is sufficient and avoids the unnecessary Riverpod consumer overhead.

## Positive Notes

- **Provider design is excellent.** The split between `FutureProvider.family` for one-shot scans, `NotifierProvider` for managed device state, `StreamProvider` for connection state, `StateProvider` for the manual started flag, and a composite `Provider` for derived UI state is idiomatic Riverpod and matches the SDK's event model precisely.
- **One-device-at-a-time enforcement** in `ActiveDeviceNotifier` correctly addresses the EventChannel singleton constraint documented in `Device` class comments (`device.dart`, lines 17–23).
- **Async disposal strategy is well-reasoned.** Recognizing that `ref.onDispose` is synchronous and cannot await the SDK's async teardown, then solving it with an explicit pre-disposal hook in `State.dispose()`, is the right approach. The only issue is the double-dispose of the locator (flagged above).
- **Scan-as-FutureProvider pattern** correctly models the SDK's single-emission `requestDevices()` stream. Using `ref.invalidate()` to re-scan is clean.
- **Error handling (Task 5)** with SnackBar feedback and state rollback on failure prevents the UI from entering inconsistent states.
- **Commit plan** groups logically — providers first (testable independently), then UI + cleanup.
