# Code Review: Device Tab (Round 2)

**Plan:** `.ai-factory/plans/41-device-tab.md`
**Files reviewed:** 5 implementation files + 4 supporting SDK files (Device, DeviceLocator, DeviceInfo, NeiryException, enums)

## Previous Review Status

All 3 findings from review-1 were addressed:

1. ~~Native device handle leak on connect failure~~ — **Fixed.** `active_device_provider.dart:39-46` wraps `connect()` in try/catch, disposes the orphaned device, and rethrows.
2. ~~Stale `deviceIsStartedProvider` after device replacement~~ — **Fixed.** `device_screen.dart:50` resets `deviceIsStartedProvider` to `false` before calling `createAndConnect`.
3. ~~Redundant `disconnectAndDispose()` in `_connect()` catch~~ — **Fixed.** Catch block simplified to `_showError` only (`device_screen.dart:55-57`).

## New Findings

None.

## Verification Notes

- **Double-dispose safety:** `_container.dispose()` in `main.dart:51` triggers `ref.onDispose` for both providers. `ActiveDeviceNotifier`'s safety-net calls `Device.dispose()` on an already-disposed device — safe due to `if (_disposed) return` guard (`device.dart:208`). `DeviceLocatorNotifier`'s `ref.onDispose` calls `DeviceLocator.dispose()` exactly once — no double-dispose risk since `_cleanupAndDispose` correctly omits locator disposal.
- **Broadcast stream multiple listeners:** `deviceConnectionStateProvider` subscribes to `device.connectionStateStream` which is `late final` (initialized once). `Device.connect()` also subscribes internally via `_startStateTracking()`. Both listen to the same broadcast stream — safe.
- **Connection event timing:** `Device.connect()` is non-blocking (dispatches to native, returns before BLE connection completes). `state = device` runs in the same microtask as `connect()` completion. The `connected` event arrives on a future event-loop turn, after `deviceConnectionStateProvider` has subscribed. No missed events.
- **`whenOrNull(data: (s) => s)` returns `null` for loading/error:** `null != NeiryConnectionState.connected` is `true`, so loading/error correctly maps to `DeviceUiState.idle`.
- **`unsupportedConnection` handling:** `deviceUiStateProvider` checks `!= connected` which covers both `disconnected` and `unsupportedConnection`.
- **Async cleanup pattern:** `_cleanupAndDispose()` is called without `await` from `State.dispose()` — standard Flutter pattern since `dispose()` is synchronous. Async work completes on the event loop. Acceptable for an example app.

REVIEW_PASS
