# Plan: Reset calibration UI state on disconnect

## Context
After a device disconnect the calibration screen keeps displaying the previous run's "calibrated" result because `calibrationProvider` caches the last `IndividualNfbData` and is never rebuilt on connection loss. This milestone resets the on-screen calibration state to idle on disconnect while preserving the portable `nfbCalibrationProvider` data.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Reset on disconnect

- [x] **Task 1: Watch connection state and clear cached calibration on disconnect**
  Files: `example/lib/providers/calibration_provider.dart`
  In `CalibrationNotifier.build()`, add a `ref.listen(deviceConnectionStateProvider, …)` registration that resets the on-screen state to idle when the device drops:
  - Add `import 'device_state_providers.dart';` to the imports block (same `providers/` directory). `NeiryConnectionState` is already in scope via `import 'package:neiry_kit/neiry_kit.dart';`.
  - Inside `build()`, after the existing `ref.onDispose(...)` block and before `return NfbCalibrator.getCalibrationData();`, insert:
    ```dart
    // Reset the on-screen calibration state when the device disconnects so the UI
    // does not keep showing the previous session's "calibrated" result. Pairs with
    // the native locator-session reset that makes the SDK forget the old calibration.
    // Do NOT clear nfbCalibrationProvider — that holds the portable IndividualNfbData
    // the "Use NFB Calibration" toggles apply on the next connect.
    ref.listen(deviceConnectionStateProvider, (prev, next) {
      if (next.valueOrNull == NeiryConnectionState.disconnected) {
        state = const AsyncValue.data(null);
      }
    });
    ```
  - Use `next.valueOrNull` (the provider is async — ignore loading/error frames).
  - Only reset on `NeiryConnectionState.disconnected`; do not react to `connecting`/`connected`.
  - Do NOT call `ref.invalidate(calibrationProvider)` — that re-runs `getCalibrationData()` against an absent device and can surface an error frame. Setting `state = const AsyncValue.data(null)` is the clean idle reset.
  - Do NOT touch `nfbCalibrationProvider` — clearing it would break the "Use NFB Calibration" toggle feature on the next connect.

## Verification

Connect → run a calibration (calibration card shows "complete / valid", data card shows peak frequency and band) → Disconnect. Expect the calibration card to return to idle ("Start Full / Quick Calibration") and the data card to blank, while the "Use NFB Calibration" toggles on the MEMS / Productivity screens stay enabled (their `nfbCalibrationProvider` data is preserved). Run `flutter analyze` in `neiry_kit/` to confirm no new warnings.
