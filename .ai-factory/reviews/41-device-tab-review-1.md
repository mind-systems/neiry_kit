# Code Review: Device Tab

**Plan:** `.ai-factory/plans/41-device-tab.md`
**Files reviewed:** 5 changed files + 4 supporting files (Device, DeviceLocator, DeviceInfo, NeiryException)

## Critical Issues

### 1. Native device handle leaks when `connect()` fails in `createAndConnect()`

`active_device_provider.dart:38-40`:
```dart
final device = await locator.createDevice(serial);
await device.connect(bipolarChannels: bipolarChannels);
state = device;
```

If `connect()` throws, `device` holds a native handle allocated by `createDevice()` on the platform side. Since `state` is never set to this device, no code path ever disposes it — the native handle leaks.

The UI catch block in `device_screen.dart:55-57` calls `disconnectAndDispose()`, but that method reads `state` which is still `null`, so it returns immediately — a no-op.

This was flagged in plan-review-2 but the fix was not applied to the code.

**Fix:** Wrap `connect()` in try/catch inside `createAndConnect` and dispose the device on failure:
```dart
final device = await locator.createDevice(serial);
try {
  await device.connect(bipolarChannels: bipolarChannels);
} catch (e) {
  try { await device.dispose(); } catch (_) {}
  rethrow;
}
state = device;
```

Once this is in place, the catch block in `_connect()` (`device_screen.dart:52-63`) no longer needs the `disconnectAndDispose()` call — just show the SnackBar.

### 2. `deviceIsStartedProvider` not reset when `createAndConnect` replaces a device

`active_device_provider.dart:19-41` — `createAndConnect` cleans up the old device (stop/disconnect/dispose) but never resets `deviceIsStartedProvider` to `false`.

**Runtime scenario:**
1. User starts streaming → `deviceIsStartedProvider = true`
2. Native SDK disconnects unexpectedly → `connectionStateStream` emits `disconnected` → `deviceUiStateProvider` returns `idle`
3. User selects a device and presses Connect (enabled because `idle`)
4. `createAndConnect` runs, old device is cleaned up, new device connects
5. `connectionStateStream` emits `connected`
6. `deviceUiStateProvider` sees `connected + isStarted==true` → returns `started`
7. UI shows Stop enabled even though the new device has not started streaming

**Fix:** Reset `deviceIsStartedProvider` at the start of `createAndConnect`:
```dart
ref.read(deviceIsStartedProvider.notifier).state = false;
```

Or reset it in the `_connect()` handler in `device_screen.dart` before calling `createAndConnect()`.

## Suggestions

### 3. `_connect()` error handler does redundant no-op work

`device_screen.dart:52-63` — Both catch branches call `disconnectAndDispose()` as "best-effort reset." But when `createAndConnect` fails before `state = device`, state is either `null` (no previous device) or already cleaned up (old device disposed at lines 27-36). `disconnectAndDispose()` checks `if (device == null) return` and exits immediately.

After fixing issue #1 (dispose leaked handle inside `createAndConnect`), these `disconnectAndDispose()` calls become dead code. Remove them to avoid confusion about what actually handles cleanup:

```dart
Future<void> _connect() async {
  final serial = _selectedSerial;
  if (serial == null) return;
  try {
    await ref.read(activeDeviceProvider.notifier).createAndConnect(serial);
  } catch (e) {
    _showError(e is NeiryException ? e.message : e.toString());
  }
}
```

## Positive Notes

- Provider architecture is clean and idiomatic Riverpod 3.x. The split between `FutureProvider.family` for scans, `Notifier` for device lifecycle, `StreamProvider` for connection state, `StateProvider` (legacy) for the manual started flag, and a composite `Provider` is well-structured.
- The `deviceUiStateProvider` correctly checks `!= NeiryConnectionState.connected` rather than `== disconnected`, handling `unsupportedConnection` as intended by the plan.
- `DeviceLocator` disposal is correctly left to `ref.onDispose` — no double-dispose risk.
- The scan re-trigger logic in `_scan()` is correct: invalidate on same params, new family member on changed params.
- `main.dart` correctly uses plain `StatefulWidget` + `UncontrolledProviderScope` with explicit `ProviderContainer` for async cleanup.
- `Device.dispose()` idempotency (`if (_disposed) return`) makes the `ref.onDispose` safety net in `ActiveDeviceNotifier.build()` safe even after explicit cleanup.
