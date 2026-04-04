# Plan Review: NfbCalibrator (Round 2)

**Plan:** `.ai-factory/plans/14-nfbcalibrator.md`
**Files Reviewed:** 2 tasks across 2 files
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan aligns with the layered plugin architecture. `nfb_calibrator.dart` lives in `lib/src/api/` (not in `classifiers/`), matching the ARCHITECTURE.md folder structure where `NfbCalibratorBridge.swift` sits at `ios/Classes/NfbCalibratorBridge.swift` (also not in `classifiers/`). Dependency rules respected: api → channel + models only.
- **RULES.md:** File not present. `WARN` — no explicit convention violations detected.
- **ROADMAP.md:** `WARN` — Roadmap entry "NfbCalibrator" (under Dart API) matches the plan's scope exactly. No alignment issues.

## Round 1 Fixes Verified

All three critical issues and both suggestions from round 1 have been addressed:

1. ✅ `stopCalibration()` is now a public method AND wired into `controller.onCancel` for `calibrateIndividual()`.
2. ✅ EventChannel opens FIRST, then `startCalibration` MethodChannel call — correct ordering (option b).
3. ✅ Static `_calibrationSubscription` field with cancel-on-overlap at the top of both `calibrateIndividual()` and `calibrateIndividualQuick()`.
4. ✅ Barrel export insertion point corrected to "after line 7 (`device_locator.dart`)".
5. ✅ Native bridge convention for `calibratorData: 'quick'` documented inline.

## Critical Issues

### 1. `startCalibration` MethodChannel error not forwarded to StreamController / Completer

Both `calibrateIndividual()` and `calibrateIndividualQuick()` invoke `NFBCalibratorMethods.startCalibration` on the MethodChannel after opening the EventChannel. If this call throws (e.g., `PlatformException` because no device is connected), the error is an unawaited Future rejection — it goes to the zone error handler instead of the returned Stream or Future.

This is a new error path that doesn't exist in `DeviceLocator.requestDevices` (where the scan starts inside the native `onListen`, so errors flow through the EventChannel naturally). The plan says "same pattern as DeviceLocator" but the separate MethodChannel start call introduces a different failure mode.

**Fix for `calibrateIndividual()`:** Chain `.catchError` on the `invokeMethod` call and forward the error to the `StreamController`, then close it:

```dart
_channel.invokeMethod<void>(NFBCalibratorMethods.startCalibration)
    .catchError((Object error, StackTrace stack) {
  if (!controller.isClosed) {
    controller.addError(error, stack);
    controller.close();
  }
});
```

**Fix for `calibrateIndividualQuick()`:** Same pattern, but complete the `Completer` with the error:

```dart
_channel.invokeMethod<void>(NFBCalibratorMethods.startCalibration, ...)
    .catchError((Object error, StackTrace stack) {
  if (!completer.isCompleted) {
    completer.completeError(error, stack);
  }
});
```

### 2. Missing `onDone` handling in `calibrateIndividualQuick()`

The plan specifies handling `CalibrationCompleted` events and stream errors via the Completer, but does not handle the raw stream's `onDone` callback. If the native side ends the EventChannel stream without emitting `CalibrationCompleted` (e.g., device disconnect triggers `endOfStream` instead of an error event), the Completer never completes — the returned Future hangs indefinitely.

**Fix:** Add `onDone` to the `rawStream.listen()` call that completes the Completer with a descriptive error if it hasn't already been completed:

```dart
onDone: () {
  clearIfCurrent();
  if (!completer.isCompleted) {
    completer.completeError(
      StateError('Calibration stream ended without producing data'),
    );
  }
},
```

## Positive Notes

- All round 1 issues were addressed correctly and cleanly — the cancel-on-overlap pattern, EventChannel-first ordering, and `stopCalibration` wiring all follow the exact codebase conventions.
- The six-method API surface maps 1:1 to `NFBCalibratorMethods` constants already in the channel contract. No new constants needed, no orphan methods.
- The `abstract final class` (static-only) design correctly reflects that the C `clCNFBCalibrator` is implicitly device-scoped — no Dart-side lifecycle to manage, cleaner than an instance-based pattern here.
- The `calibratorData: 'quick'` multiplexing convention is now documented inline with a clear note for bridge implementers, preventing a common integration pitfall.
- The shared `_calibrationSubscription` field between full and quick modes ensures only one calibration can run at a time — matching the C SDK's single-calibrator constraint.
