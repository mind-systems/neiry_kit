# Plan: Recreate the locator session on disconnect

## Context
Repeat full NFB calibration fails with `Calibration has already been started` (code 255) because the Capsule SDK caches `clCDevice` (and its stuck session-scoped calibrator) per serial inside the singleton `clCDeviceLocator`, and `clCDevice_Release` never evicts it. Tearing down and recreating the locator at the end of `disconnect()` is the only SDK-sanctioned reset.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Recreate locator on disconnect

- [x] **Task 1: Make `_locator` mutable and recreate it at the end of `disconnect()`**
  Files: `example/lib/services/neiry_service.dart`
  - Change the field declaration `final DeviceLocator _locator;` (line 22) to `DeviceLocator _locator;`. Keep the constructor initializer `NeiryService() : _locator = DeviceLocator();` (line 18) unchanged.
  - At the very end of `disconnect()`, immediately after the device-scoped resets `_device = null; _nfbData = null; _calibrator = null;` (lines 343–345), add a guarded locator teardown + recreate:
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
  - The `!_disposed` guard is mandatory: `dispose()` (lines 379–383) sets `_disposed = true` (line 381) *before* calling `await disconnect()` (line 382) and then runs its own `await _locator.dispose()` (line 383). The guard makes `disconnect()` skip the recreate during full teardown, so the locator is disposed exactly once (`DeviceLocator.dispose()` calls `_checkNotDisposed()` first and would throw `StateError` on a double-dispose).
  - Do NOT add any native calibrator "reset" hack — the SDK has no stop/reset API; locator teardown is the intended reset.
  - No changes needed in `connect()`/`scan()`: both read `_locator` at call time and automatically use the recreated instance.

## Verify
Rebuild (native + Dart). Run: full calibrate → Disconnect → Connect → Start → full calibrate again, and expect success. With temporary lifecycle logs, the reconnect `nativeCreateDevice` should return a **different** `dev=` pointer and `nativeStartCalibration` should read `IsCalibrated=0` on the fresh device.
