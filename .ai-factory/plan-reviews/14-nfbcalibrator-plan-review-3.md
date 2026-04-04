# Plan Review: NfbCalibrator (Round 3)

**Plan:** `.ai-factory/plans/14-nfbcalibrator.md`
**Files Reviewed:** 2 tasks across 2 files
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan aligns with the layered plugin architecture. `nfb_calibrator.dart` lives in `lib/src/api/` (not in `classifiers/`), matching the folder structure where `NfbCalibratorBridge.swift` sits at `ios/Classes/` (also not in `classifiers/`). Dependency rules respected: api → channel + models only.
- **RULES.md:** File not present. `WARN` — no explicit convention violations detected.
- **ROADMAP.md:** `WARN` — Roadmap entry "NfbCalibrator" (under Dart API) matches the plan's scope exactly. No alignment issues.

## Round 2 Fixes Verified

Both critical issues from round 2 have been addressed:

1. ✅ `startCalibration` MethodChannel error now forwarded via `.catchError` — `calibrateIndividual()` pipes the error into the `StreamController` and closes it; `calibrateIndividualQuick()` completes the `Completer` with the error. Both code snippets are inlined in the plan.
2. ✅ `onDone` handling added to `calibrateIndividualQuick()` — if the native EventChannel ends without emitting `CalibrationCompleted`, the Completer is completed with a descriptive `StateError` instead of hanging indefinitely. Code snippet inlined.

## All Previous Fixes Still Present

Round 1 fixes (verified in round 2, still intact):

1. ✅ `stopCalibration()` is a public method AND wired into `controller.onCancel` for `calibrateIndividual()`.
2. ✅ EventChannel opens FIRST, then `startCalibration` MethodChannel call — correct ordering.
3. ✅ Static `_calibrationSubscription` field with cancel-on-overlap at the top of both `calibrateIndividual()` and `calibrateIndividualQuick()`.
4. ✅ Barrel export insertion point: after line 7 (`device_locator.dart`), alphabetically correct.
5. ✅ Native bridge convention for `calibratorData: 'quick'` documented inline.

## Verification Against Codebase

- **Channel contract:** All six methods (`startCalibration`, `stopCalibration`, `importCalibration`, `getCalibration`, `isCalibrated`) map 1:1 to `NFBCalibratorMethods` constants in `channel_names.dart`. No orphan methods, no missing constants.
- **EventChannel:** `NeiryEvents.nfbCalibration` (`'neiry_kit/events/nfbCalibration'`) exists at line 43 of `channel_names.dart`.
- **MethodChannel:** `NeiryChannels.nfbCalibrator` (`'neiry_kit/nfb_calibrator'`) exists at line 18 of `channel_names.dart`.
- **Argument key:** `NeiryArgs.calibratorData` (`'calibratorData'`) exists at line 141 of `channel_names.dart`. Used for quick-mode flag in `startCalibration` and for data payload in `importCalibration` — no collision since they target different method calls.
- **Models:** `CalibrationEvent.deserialize`, `CalibrationStageFinished`, `CalibrationCompleted`, `IndividualNfbData.fromMap`, `IndividualNfbData.toMap` all exist and are already exported from the barrel.
- **DeviceLocator pattern:** The `StreamController` + `late final thisSub` + `clearIfCurrent()` pattern described in the plan matches the actual `DeviceLocator.requestDevices` implementation (lines 114–164 of `device_locator.dart`) exactly.
- **Barrel file:** Line 7 is `export 'src/api/device_locator.dart';` — the new `nfb_calibrator` export after it is alphabetically correct (`n` > `d`), and correctly placed before line 8 (`channel_names.dart`).

## Positive Notes

- Three review rounds have refined this plan into a precise, implementation-ready specification. Every error path is explicitly handled with inlined code snippets — the implementer has zero ambiguity.
- The `abstract final class` (static-only) design correctly reflects the C SDK's implicit device-scoping for `clCNFBCalibrator` — cleaner than an instance-based pattern here.
- The shared `_calibrationSubscription` field between full and quick modes enforces the C SDK's single-calibrator constraint at the Dart level.
- The `.catchError` → `StreamController`/`Completer` bridge for `invokeMethod` failures is a pattern not present in `DeviceLocator` (which starts its scan inside `onListen`) — the plan correctly identifies this as a different error topology and handles it explicitly.
- The `onDone` safety net for `calibrateIndividualQuick()` prevents a hung Future on unexpected stream termination — a subtle edge case that would be hard to debug in production.

PLAN_REVIEW_PASS
