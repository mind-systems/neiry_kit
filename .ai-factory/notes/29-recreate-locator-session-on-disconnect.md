# Recreate the locator session on disconnect

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- The Capsule SDK has **no stop/reset/abort API** for `clCNFBCalibrator`. The C and C++ headers expose only `CreateOrGet`, `CalibrateIndividualNFB(stage)`, `CalibrateIndividualNFBQuick`, `Import`, `Get`, `IsCalibrated`, `HasCalibrationFailed`, and the two `SetOn*Event` setters. The official C#/Python wrappers mirror this — no reset.
- After a full 4-stage calibration the SDK leaves the calibrator in an internal "started" state that is **not observable** via `IsCalibrated`/`HasCalibrationFailed` and is **never cleared**. A quick calibration does clear it. Consequence: `quick → full` works, but `full → full` fails with `Failed to calibrated individual nfb: Calibration has already been started` (error code 255).
- The calibrator is session-scoped (`CreateOrGet(device)` returns the same instance for a device). The device itself is cached **per serial inside the `clCDeviceLocator`**: `clCDevice_Release` does NOT evict it, so `clCDeviceLocator_CreateDevice(serial)` after a release returns the **identical `clCDevice` pointer** and the identical stuck calibrator.
- Therefore disconnect→reconnect does not help today, because `NeiryService` keeps the singleton `DeviceLocator` alive and only releases the device. The only SDK-sanctioned reset is **destroying and recreating the locator** (`clCDeviceLocator_Destroy` + a fresh `clCDeviceLocator_Create`), which `DeviceLocator.dispose()` already does.

## Details

### Evidence (device logs, SM A705FN)

```
Before disconnect:  nativeCreateDevice: locator=0x776e1a4000 serial=820566 -> dev=0x776e1a4160
Disconnect:         nativeReleaseDevice: dev=0x776e1a4160
Reconnect:          nativeCreateDevice: locator=0x776e1a4000 serial=820566 -> dev=0x776e1a4160   ← same pointer
Recalibrate:        nativeStartCalibration: cal=0x776e974880 sameInstanceAsPrev=1 IsCalibrated=1 → FAILED code=255
```

Same locator → same device pointer → same calibrator (`IsCalibrated=1`), so the full re-calibration is rejected.

### Current state

`example/lib/services/neiry_service.dart`:
- Field `final DeviceLocator _locator;` created once in the constructor (`NeiryService() : _locator = DeviceLocator();`).
- `disconnect()` runs a strict teardown (stop stream → cancel fan-in subs → dispose classifiers → `device.disconnect()` → `device.dispose()`) and then resets device-scoped fields (`_device = null; _nfbData = null; _calibrator = null;`). It does **not** touch `_locator`.
- `dispose()` (full service teardown) calls `disconnect()` then `await _locator.dispose()`.

`lib/src/api/device_locator.dart`:
- `DeviceLocator` is a process-wide singleton (`_instance ??= …`).
- `dispose()` cancels any active scan, awaits native ready, invokes `DeviceLocatorMethods.dispose` (→ native `clCDeviceLocator_Destroy`), and sets `_instance = null` so the next `DeviceLocator()` builds a fresh native locator. It calls `_checkNotDisposed()` first — disposing twice throws `StateError`.

### Exact change

In `example/lib/services/neiry_service.dart`:
1. Change the field to mutable: `final DeviceLocator _locator;` → `DeviceLocator _locator;` (field decl at `neiry_service.dart:22`; keep the constructor initializer `NeiryService() : _locator = DeviceLocator();` at `neiry_service.dart:18`).
2. At the very end of `disconnect()`, after the device-scoped resets `_device = null; _nfbData = null; _calibrator = null;` (`neiry_service.dart:343–345`, method closes at `:346`), add a guarded locator teardown + recreate:
   ```dart
   // Tear down the locator session so the next connect builds a genuinely fresh
   // native locator. The SDK caches clCDevice per serial inside the locator and
   // clCDevice_Release does not evict it — reconnecting via the same locator
   // returns the same device + the same session-scoped NFB calibrator stuck in
   // its "already started" state, blocking re-calibration. Skipped during full
   // service dispose(), which tears the locator down itself.
   if (!_disposed) {
     try {
       await _locator.dispose();
     } catch (e) {
       nlog('[NeiryService] locator.dispose error: $e', name: 'neiry_kit');
     }
     _locator = DeviceLocator();
   }
   ```

The `!_disposed` guard matters: `dispose()` (`neiry_service.dart:379–383`) sets `_disposed = true` (`:381`) *before* calling `await disconnect()` (`:382`), then runs its own `await _locator.dispose()` (`:383`). So during full teardown `disconnect()` sees `_disposed == true` and skips the recreate, and the locator is disposed exactly once (no double-dispose `StateError` — `DeviceLocator.dispose()` calls `_checkNotDisposed()` first, `device_locator.dart`). `_disposed` field declared at `neiry_service.dart:27`.

### Guards / pitfalls

- Do NOT add any calibrator "reset" hack in native code — the SDK has none; locator teardown is the intended reset.
- `connect()` and `scan()` read `_locator` at call time, so they automatically use the freshly recreated instance. No other holders of `_locator` exist (providers watch `neiryServiceProvider`, not the locator).
- `DeviceLocator()` after dispose kicks off an async native `create`; all locator methods await `_nativeReady` first, so an immediate scan/connect is safe.

### Verify

Rebuild (native + Dart). Run: full calibrate → Disconnect → Connect → Start → full calibrate again. Expect success. With temporary lifecycle logs, the reconnect `nativeCreateDevice` should return a **different** `dev=` pointer and `nativeStartCalibration` should read `IsCalibrated=0` on the fresh device.

## Open Questions

- Unverified whether the SDK caches any calibrator state **above** the locator (library/`clCCapsule` global). If a fresh locator still returns a stuck calibrator (reconnect shows a new `dev` pointer but `IsCalibrated=1`), the reset lives higher and a heavier teardown is needed. The verification step above distinguishes the two outcomes.
