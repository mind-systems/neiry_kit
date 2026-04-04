# Plan: NfbCalibrator

## Context

Implement the `NfbCalibrator` static Dart API class that wraps the native `clCNFBCalibrator` — exposing full 4-stage calibration as a `Stream<CalibrationEvent>`, quick 1-stage calibration as a `Future<IndividualNfbData>`, stop/import/query methods for controlling and persisting calibration data across sessions.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dart API

- [x] **Task 1: Create NfbCalibrator class**
  Files: `lib/src/api/nfb_calibrator.dart`
  Create a new file `lib/src/api/nfb_calibrator.dart` with an `abstract final class NfbCalibrator` (static-only, no instantiation). Use `NeiryChannels.nfbCalibrator` MethodChannel and `NeiryEvents.nfbCalibration` EventChannel from the existing channel contract. Add a static `StreamSubscription<dynamic>? _calibrationSubscription` field for overlap protection (same pattern as `DeviceLocator._scanSubscription`). Implement six public static methods:

  **`calibrateIndividual()`** — returns `Stream<CalibrationEvent>`. Internally:

  1. Cancel any active calibration first: cancel `_calibrationSubscription` and invoke `NFBCalibratorMethods.stopCalibration` on the MethodChannel (overlap protection, same pattern as `DeviceLocator.requestDevices` cancel-on-overlap).
  2. Open the `NeiryEvents.nfbCalibration` EventChannel via `receiveBroadcastStream` FIRST — this ensures no events are lost between start and listen.
  3. THEN invoke `NFBCalibratorMethods.startCalibration` via MethodChannel (no arguments for full mode). Chain `.catchError` on this `invokeMethod` call to forward `PlatformException` (or any error) into the `StreamController` and close it — this handles the case where the native start call fails (e.g. no device connected), which would otherwise be an unawaited Future rejection:

  ```dart
  _channel.invokeMethod<void>(NFBCalibratorMethods.startCalibration)
      .catchError((Object error, StackTrace stack) {
    if (!controller.isClosed) {
      controller.addError(error, stack);
      controller.close();
    }
  });
  ```

  Wrap in a `StreamController<CalibrationEvent>` (same pattern as `DeviceLocator.requestDevices`): the raw broadcast stream maps each event through `CalibrationEvent.deserialize`. Use `late final StreamSubscription<dynamic> thisSub` and a `clearIfCurrent()` helper identical to the `DeviceLocator` pattern. The stream emits up to 4 `CalibrationStageFinished` events followed by one `CalibrationCompleted`, then the controller closes. Wire `controller.onCancel` to: call `clearIfCurrent()`, cancel the underlying subscription, and invoke `NFBCalibratorMethods.stopCalibration` via MethodChannel (so the native calibrator also stops, not just the Dart stream). Store `thisSub` in `_calibrationSubscription` after creation. Do NOT pass `serial` as an argument — the C `clCNFBCalibrator` is device-scoped implicitly (the SDK uses the last-connected device).

  **`calibrateIndividualQuick()`** — returns `Future<IndividualNfbData>`.

  1. Cancel any active calibration first: cancel `_calibrationSubscription` and invoke `NFBCalibratorMethods.stopCalibration` on the MethodChannel (same overlap protection — both methods share `_calibrationSubscription`).
  2. Open the `NeiryEvents.nfbCalibration` EventChannel via `receiveBroadcastStream` FIRST.
  3. THEN invoke `NFBCalibratorMethods.startCalibration` with `{NeiryArgs.calibratorData: 'quick'}` on the MethodChannel. Chain `.catchError` on this `invokeMethod` call to complete the `Completer` with the error — same rationale as `calibrateIndividual()`, the native start call can fail independently of the EventChannel:

  ```dart
  _channel.invokeMethod<void>(NFBCalibratorMethods.startCalibration, ...)
      .catchError((Object error, StackTrace stack) {
    if (!completer.isCompleted) {
      completer.completeError(error, stack);
    }
  });
  ```

  Note for native bridge implementers: the Swift/Kotlin `onMethodCall` handler for `startCalibration` must check for the `NeiryArgs.calibratorData == 'quick'` argument to distinguish full vs quick mode — routing to `CalibrateIndividualNFBQuick()` vs `CalibrateIndividualNFB()` accordingly.

  Listen on the raw stream for the first `CalibrationCompleted` event, cancel the subscription (clear `_calibrationSubscription`), and return the `IndividualNfbData`. Use a `Completer<IndividualNfbData>` to bridge the stream to a future. If a `CalibrationStageFinished` arrives (shouldn't in quick mode), ignore it. If the stream errors, complete the completer with the error. Store the subscription in `_calibrationSubscription`. Wire the `onDone` callback on the raw stream listener to handle the case where the native side ends the EventChannel without emitting `CalibrationCompleted` (e.g. device disconnect triggers `endOfStream`). In `onDone`: call `clearIfCurrent()`, then complete the Completer with a `StateError` if it hasn't already been completed — this prevents the returned Future from hanging indefinitely:

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

  **`stopCalibration()`** — returns `Future<void>`. Cancel `_calibrationSubscription` (if active), set it to `null`, and invoke `NFBCalibratorMethods.stopCalibration` on the MethodChannel. This tells the native `clCNFBCalibrator` to abort any in-progress calibration (full or quick). Safe to call when no calibration is running.

  **`importCalibrationData(IndividualNfbData data)`** — returns `Future<void>`. Invoke `NFBCalibratorMethods.importCalibration` with `{NeiryArgs.calibratorData: data.toMap()}`.

  **`getCalibrationData()`** — returns `Future<IndividualNfbData?>`. Invoke `NFBCalibratorMethods.getCalibration`. If the native side returns `null`, return `null`; otherwise decode the returned `Map` via `IndividualNfbData.fromMap`.

  **`isCalibrated()`** — returns `Future<bool>`. Invoke `NFBCalibratorMethods.isCalibrated` and return the `bool` result.

  Follow the doc-comment style from `DeviceLocator` and `NfbClassifier` — class-level doc with usage example, per-method docs explaining behavior and edge cases.

- [x] **Task 2: Export NfbCalibrator from barrel**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/nfb_calibrator.dart';` to the barrel file. Insert it after line 7 (`export 'src/api/device_locator.dart';`) — `nfb_calibrator` sorts alphabetically after `device_locator`. All models (`CalibrationEvent`, `CalibrationStage`, `IndividualNfbData`, `NfbCalibrationFailReason`) are already exported.
