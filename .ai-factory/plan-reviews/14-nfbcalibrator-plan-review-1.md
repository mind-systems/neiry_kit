# Plan Review: NfbCalibrator (Round 1)

**Plan:** `.ai-factory/plans/14-nfbcalibrator.md`
**Files Reviewed:** 2 tasks across 2 files
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan aligns with the layered plugin architecture (channel → api → barrel). The static-only class lives in `lib/src/api/nfb_calibrator.dart` alongside `device.dart` and `device_locator.dart`, respecting the "one file per C concept" rule. No boundary violations.
- **RULES.md:** File not present. `WARN` — no explicit convention violations detected.
- **ROADMAP.md:** `WARN` — Roadmap entry for NfbCalibrator matches the plan's scope. No alignment issues.

## Critical Issues

### 1. Missing `stopCalibration` — native calibration runs uncontrolled after Dart stream cancel

`NFBCalibratorMethods.stopCalibration` exists in the channel contract (`channel_names.dart:121`) but the plan never exposes it. The plan says `controller.onCancel` cancels the underlying Dart stream subscription — but this only stops Dart from receiving events. The native `clCNFBCalibrator` keeps running for up to 80 seconds (full) or 30 seconds (quick), wasting device resources and potentially blocking a subsequent calibration attempt.

**Fix:** Wire `controller.onCancel` in `calibrateIndividual()` to also invoke `NFBCalibratorMethods.stopCalibration` on the MethodChannel. For `calibrateIndividualQuick()`, the Completer-based pattern has no cancellation path at all — add a note that quick mode runs to completion (30s is short), or provide a top-level `stopCalibration()` static method that both call paths can use.

At minimum, add a sixth public static method:

```dart
static Future<void> stopCalibration() async {
  await _channel.invokeMethod<void>(NFBCalibratorMethods.stopCalibration);
}
```

### 2. Race condition — EventChannel opened AFTER MethodChannel `startCalibration`

The plan says: "invoke `NFBCalibratorMethods.startCalibration` via MethodChannel, then open `NeiryEvents.nfbCalibration` EventChannel." This means events emitted between the MethodChannel response and EventChannel registration are lost. While the 20-second stage duration makes data loss unlikely in practice, this is architecturally wrong and could fail in edge cases (e.g., immediate failure callback on bad electrode contact).

`DeviceLocator.requestDevices` uses the correct pattern: it opens the EventChannel first (via `receiveBroadcastStream` with args), and the native `onListen` handler starts the scan. The plan should follow this same pattern — open the EventChannel first and either:

- **(a)** Start calibration inside the native `StreamHandler.onListen`, passing a `'quick'` vs `'full'` mode through the `receiveBroadcastStream` arguments, or
- **(b)** Open the EventChannel subscription first, then invoke `startCalibration` on the MethodChannel second (events won't be lost because the EventChannel is already listening).

Option (b) is simpler and doesn't require native-side changes.

### 3. No overlap protection for concurrent calibration calls

Both `calibrateIndividual()` and `calibrateIndividualQuick()` open the same `NeiryEvents.nfbCalibration` EventChannel. If called while a previous calibration is active, both streams listen on the same channel — events get duplicated or misrouted.

`DeviceLocator.requestDevices` handles this with a static `_scanSubscription` field and cancel-on-overlap at the top of the method. The plan should add a static `_calibrationSubscription` field to `NfbCalibrator` and cancel any active calibration before starting a new one. Both methods must share this field.

## Suggestions

### 1. Barrel export insertion point is inaccurately described

The plan says "after `device_locator.dart`, before `device.dart`" — but in the actual barrel file, `device.dart` (line 6) comes BEFORE `device_locator.dart` (line 7). The correct insertion point is after line 7 (`export 'src/api/device_locator.dart';`), since `nfb_calibrator` sorts alphabetically after `device_locator`. Minor textual error, but could confuse the implementer.

### 2. Document the `calibratorData: 'quick'` native bridge convention

The plan reuses `NFBCalibratorMethods.startCalibration` for both full and quick mode, distinguished by the presence of `{NeiryArgs.calibratorData: 'quick'}`. This is a multiplexing convention that the native bridges must understand — the Swift/Kotlin `onMethodCall` handler needs to check for this argument and route to `CalibrateIndividualNFBQuick()` vs `CalibrateIndividualNFB()`. Add a one-line note so the bridge implementer knows about this contract.

## Positive Notes

- The `abstract final class` (static-only) design is the right choice — the C `clCNFBCalibrator` is implicitly device-scoped, so there's no Dart-side lifecycle to manage. This is a clean departure from the instance-based classifier pattern, and the plan explicitly justifies it.
- All five methods map cleanly to `NFBCalibratorMethods` constants already defined in the channel contract. No new channel constants needed.
- The `StreamController` + `CalibrationEvent.deserialize` pipeline for full calibration, and the `Completer<IndividualNfbData>` bridge for quick mode, are well-designed and match existing codebase patterns.
- The plan correctly notes that `serial` is NOT passed as an argument — consistent with the calibrator being device-scoped.
- All required models (`CalibrationEvent`, `IndividualNfbData`, `CalibrationStage`, `NfbCalibrationFailReason`) are already implemented and exported — the plan correctly scopes its work to only the API class + barrel export.
