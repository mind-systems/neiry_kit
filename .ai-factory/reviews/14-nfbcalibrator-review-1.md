# Code Review: NfbCalibrator

**Plan:** `.ai-factory/plans/14-nfbcalibrator.md`
**Files reviewed:** `lib/src/api/nfb_calibrator.dart`, `lib/neiry_kit.dart`

## Critical Issues

### 1. `controller.onCancel` invokes native `stopCalibration` unconditionally — late cancel of old stream kills new calibration

`nfb_calibrator.dart:113-117`

```dart
controller.onCancel = () {
  clearIfCurrent();
  thisSub.cancel();
  _channel.invokeMethod<void>(NFBCalibratorMethods.stopCalibration);
};
```

When overlap occurs (consumer calls `calibrateIndividual()` twice), the first call's `StreamController` stays alive — its `onCancel` callback still captures a closure over `thisSub` and the MethodChannel. If the old consumer cancels their subscription *after* a new calibration has started, `onCancel` fires and invokes `stopCalibration` on the MethodChannel. This kills the *new* calibration, not the old one.

Compare with `DeviceLocator.requestDevices` (`device_locator.dart:159-162`) — its `onCancel` does NOT invoke any native method, specifically to avoid this cross-talk:

```dart
controller.onCancel = () {
  clearIfCurrent();
  thisSub.cancel();
};
```

The NfbCalibrator's `onCancel` adds a `stopCalibration` MethodChannel call that the base pattern deliberately omits.

**Fix:** Only invoke native `stopCalibration` when this subscription is still the current one:

```dart
controller.onCancel = () {
  final wasCurrent = identical(_calibrationSubscription, thisSub);
  clearIfCurrent();
  thisSub.cancel();
  if (wasCurrent) {
    _channel.invokeMethod<void>(NFBCalibratorMethods.stopCalibration)
        .catchError((_) {}); // see issue #3
  }
};
```

### 2. `calibrateIndividualQuick()` Future hangs forever on external stop or overlap cancel

`nfb_calibrator.dart:134-192`

When `stopCalibration()` or a new `calibrateIndividual()`/`calibrateIndividualQuick()` call fires while a quick calibration is active, `_calibrationSubscription` is cancelled. But cancelling a `StreamSubscription` does **not** fire its `onDone` callback — `onDone` only fires when the stream itself emits a done event. The `Completer<IndividualNfbData>` is never completed, and the returned Future hangs indefinitely.

Trace:
1. User calls `final data = await NfbCalibrator.calibrateIndividualQuick();`
2. Later, `stopCalibration()` runs → `_calibrationSubscription?.cancel()` cancels `thisSub`
3. `onDone` does NOT fire (subscription was cancelled, not the stream)
4. `Completer` is never completed → `await` hangs forever

The `onDone` handler added per review round 2 correctly covers the case where the *native side* ends the stream. It does not cover the case where the *Dart side* cancels the subscription.

**Fix:** Store the active `Completer` in a static field and complete it with an error during cancellation. Add a cleanup helper called at the top of both calibration methods and in `stopCalibration()`:

```dart
static Completer<IndividualNfbData>? _quickCompleter;

static void _cancelActiveCalibration() {
  _calibrationSubscription?.cancel();
  _calibrationSubscription = null;
  if (_quickCompleter != null && !_quickCompleter!.isCompleted) {
    _quickCompleter!.completeError(
      StateError('Calibration cancelled'),
    );
  }
  _quickCompleter = null;
}
```

Then in `calibrateIndividualQuick()`, assign `_quickCompleter = completer;` and in `stopCalibration()`, call `_cancelActiveCalibration()` before the native stop.

### 3. Three fire-and-forget `stopCalibration` MethodChannel calls lack error handling

`nfb_calibrator.dart:66`, `nfb_calibrator.dart:116`, `nfb_calibrator.dart:138`

The overlap-cancel sections and `controller.onCancel` invoke `NFBCalibratorMethods.stopCalibration` without awaiting or attaching `.catchError`. If the native call throws (e.g. no calibrator was ever started, or native bridge not yet registered), the returned Future rejects with no listener — producing an unhandled async error that crashes in debug mode and logs a noisy zone error in release.

Compare with the `startCalibration` calls on lines 104-111 and 182-189 which correctly chain `.catchError`. The `stopCalibration` calls need the same treatment.

**Fix:** Append `.catchError((_) {})` to all three fire-and-forget stop calls — these are best-effort cleanup where failure is benign:

```dart
_channel.invokeMethod<void>(NFBCalibratorMethods.stopCalibration)
    .catchError((_) {});
```

## Suggestions

### 1. `stopCalibration()` and overlap cancel don't close the `calibrateIndividual()` consumer stream

Same mechanism as issue #2 but for the full calibration stream: when `stopCalibration()` or overlap fires, the `StreamController<CalibrationEvent>` is never closed. The consumer's stream goes silent but never receives a done event. Less severe than the `calibrateIndividualQuick()` hang (the consumer can cancel their own subscription), but still surprising behavior — a consumer doing `await for (final event in stream)` would also hang.

Consider tracking the active `StreamController` in a static field and closing it during cancellation, similar to the `_quickCompleter` fix in issue #2.

## Verdict

Three critical issues — two are runtime bugs that cause permanent hangs or cross-calibration interference, one produces unhandled async errors. The barrel export and the six-method API surface are correct. The plan's review round 2 fixes (`.catchError` on `startCalibration`, `onDone` in quick mode) are implemented correctly but an adjacent gap remains in the cancellation paths.
