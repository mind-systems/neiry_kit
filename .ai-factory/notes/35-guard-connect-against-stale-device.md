# Guard connect() against a stale device (fix double-registration crash on reconnect)

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- Turning the headset off mid-session crashes the app on the *next* Connect, with `Fatal signal 64` + `0xebadde09` on a background SDK thread. Confirmed on SM A705FN (log01).
- Sequence: device powered off → Android `BluetoothGatt onClientConnectionState status=8` (GATT_CONN_TIMEOUT) → SDK "Session is not running". **No app-level teardown ran** — `NeiryService.disconnect()` is only called from the Disconnect button. So `_device`, the six classifiers, and the registered native modules all stay alive.
- On the next Connect the log shows `connect — _device: set isConnected: false`: the stale `_device` is still non-null while `isConnected` is false. `connect()`'s only guard is `if (isConnected) throw` (`example/lib/services/neiry_service.dart:123`), so it proceeds and re-creates the classifiers, which makes the SDK reject every module: `Failed to create nfb/emotions/productivity/cardio/mems module: clC… module already exists`. The double-registration + stale background-thread JNI refs (`0xebadde09`) then abort the process (signal 64).
- Independent, guaranteed fix that needs **no** disconnect-event from the SDK: before connecting, if `_device != null`, run the existing teardown first so the old session (modules + classifiers + device handle) is released. This alone removes the crash regardless of whether the SDK ever reports the drop (the latter is handled separately — see note 36).

## Details

### Current state

`example/lib/services/neiry_service.dart`, `connect()` (≈ lines 114–125):
```dart
_checkNotDisposed();
if (_connecting) throw StateError('Connect already in flight');
if (isConnected) throw StateError('Already connected — call disconnect() first');
```
`isConnected => _device?.isConnected ?? false`. After a silent drop `_device != null` but `isConnected == false`, so neither guard fires.

`disconnect()` (≈ lines 259–367) is already a safe, idempotent full teardown: returns early when `_device == null`, synthesizes a `disconnected` UI event, stops the stream, cancels fan-in subs, disposes all classifiers, disconnects + disposes the device, nulls `_device/_nfbData/_calibrator`, and (when `!_disposed`) disposes + recreates the locator.

### Exact change

In `connect()`, before `_connecting = true`, tear down any stale session:
```dart
if (_device != null) {
  nlog('[NeiryService] connect: stale device present — tearing down before reconnect', name: 'neiry_kit');
  await disconnect();
}
```
Place it after the `_checkNotDisposed()` / `_connecting` / `isConnected` guards. Because `disconnect()` already handles `_device == null` and recreates the locator, this is safe and idempotent. After it returns, `_device == null` and all old native modules are released, so the subsequent `createDevice` + classifier construction starts clean — no "module already exists".

### Guards / pitfalls

- Keep the `if (isConnected) throw` guard for the genuinely-still-connected case (user double-tapping Connect) — or relax it to also route through `disconnect()`; decide during implementation, but do not silently reconnect over a *live* session without tearing it down.
- `disconnect()` sets no `_connecting` flag, and `connect()` sets `_connecting = true` only after this teardown — no re-entrancy conflict.
- This does not fix the "Device screen stuck at connected" UX; that needs reactive teardown on the drop itself (note 36). This task only guarantees the *reconnect* path is crash-safe.
- Pure Dart; no native changes.

### Verify

Connect → Start → power the headset off → Scan → Connect again. Expect: no `clC… module already exists` errors, no `0xebadde09` / signal 64; the second session connects cleanly.
