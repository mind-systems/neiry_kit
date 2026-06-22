# Auto-teardown NeiryService on unexpected disconnect

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- When the headset powers off (or BLE drops) mid-session, the app does not fully transition to a disconnected state: the Device screen stays at "connected" and the underlying `NeiryService` keeps the dead session alive (classifiers, native modules, `_device` all still set). Only the explicit Disconnect button runs teardown.
- `NeiryService` (`example/lib/services/neiry_service.dart`) only **forwards** the device connection-state into `_connectionStateController` (the fan-in subscription `_device!.connectionStateStream.listen(_connectionStateController.add)`); nothing inside the service **reacts** to a `disconnected` it did not initiate. So an unexpected drop leaks resources and leaves the UI inconsistent. The leaked native modules are what later crash the reconnect (see note 35).
- A reliable "connection dropped" signal is **sufficient** to release everything — the full teardown already exists in `disconnect()` (stop → cancel subs → dispose classifiers → release device → recreate locator → `invalidate_calibrator`). No extra data from the SDK is needed beyond the drop event itself.
- **Trigger verified:** the SDK emits `NeiryConnectionState.disconnected` on power-off — confirmed on SM A705FN (`device.connectionStateStream` logged `disconnected` ~7 s after the Android GATT `onClientConnectionState status=8`). So `device.connectionStateStream` is a usable trigger; the only nuance is the ~7 s latency between the BLE drop and the event.

## Details

### Trigger (verified)

The SDK delivers `NeiryConnectionState.disconnected` on `device.connectionStateStream` ~7 s after a power-off (the Android GATT `status=8` fires first; the `clCDevice` event lands ~7 s later). The same broadcast stream already drives the Device screen's "Connection state" line. No fallback (error event / GATT exposure / heartbeat) is needed.

### Exact change

1. In `NeiryService`, add an internal subscription to the device's connection-state stream (and/or error stream) created in `connect()`, separate from the UI fan-in. On a `disconnected`/error event that the service did **not** initiate, schedule the existing teardown.
2. Add a `bool _tearingDown` (or reuse intent flags) so the spontaneous-disconnect path and the user `disconnect()` path do not run teardown twice, and so the synthesized `disconnected` event in `disconnect()` does not re-trigger the listener.
3. Run teardown via the existing `disconnect()` (it is idempotent and already nulls `_device` + recreates the locator), so the UI converges to idle (`deviceUiStateProvider` → `idle`) and all native modules are freed.
4. Reset `deviceIsStartedProvider` to false on the spontaneous path too (today only the button handlers in `device_screen.dart` do this).

### Guards / pitfalls

- Re-entrancy: `disconnect()` itself adds a synthesized `disconnected` to `_connectionStateController`; ensure the internal listener keys off the **device** stream or an intent flag so it is not re-entered by the teardown it just started.
- Do not double-dispose the locator: `disconnect()` already guards with `!_disposed`; the spontaneous path must go through `disconnect()`, not a parallel teardown.
- This complements note 35 (connect-time stale-device guard). With both, the crash is fixed two ways and the UI also converges on drop (after the ~7 s SDK latency).
- Pure Dart; no native change needed.

### Verify

Connect → Start → power the headset off. Expect: ~7 s after the drop the Device screen moves to idle/disconnected, classifiers disposed, `_device == null`; a subsequent Connect works without any stale-session errors.
