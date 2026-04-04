## Code Review Summary

**Plan Reviewed:** `12-productivityclassifier.md`
**Files Affected:** 3 (channel_names.dart, productivity_classifier.dart [new], neiry_kit.dart)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — WARN: no issues. Target file path `lib/src/api/classifiers/productivity_classifier.dart` matches the defined folder structure. Dependency flow (api → channel + models) is respected. Barrel export pattern is followed.
- **RULES.md** — file does not exist, skipped.
- **ROADMAP.md** — WARN: plan aligns with the unchecked `ProductivityClassifier` milestone under "Dart API". No linkage gaps. The roadmap spec reference (`.ai-factory/notes/04-dart-api-classifiers.md`) matches the plan's design.

### Critical Issues

None.

### Suggestions

None. The previous review's suggestion (missing `errorStream`) has been addressed — the plan now correctly includes the 7th `_errorStream` / `errorStream` backed by the existing `NeiryEvents.productivityError` channel, matching the NfbClassifier and EmotionsClassifier pattern.

### Positive Notes

- Previous review feedback fully incorporated — the `errorStream` is now included as the 7th stream with proper decode logic and documentation explaining why it's needed.
- The two EventChannel IDs to add (`productivityBaselines`, `productivityIndividualNfb`) are the only ones missing; all other five (`productivityMetrics`, `productivityIndexes`, `productivityCalibrationProgress`, `productivityCalibrated`, `productivityError`) are verified present in `channel_names.dart`.
- All referenced constants exist: `NeiryChannels.productivity` (line 16), `ClassifierMethods.create/createCalibrated/startBaselineCalibration/importBaselines/resetAccumulatedFatigue/dispose` (lines 104–111), `NeiryArgs.serial/calibrationData/baselines` (lines 128, 136, 135).
- All model `fromMap` factories verified: `ProductivityMetrics.fromMap(Map<Object?, Object?>)`, `ProductivityIndexes.fromMap(Map<Object?, Object?>)`, `ProductivityBaselines.fromMap(Map<Object?, Object?>)`, `NfbUserState.fromMap(Map<Object?, Object?>)` — all accept the correct map type for the `_eventStream` helper.
- `IndividualNfbData.toMap()` exists and is correctly referenced for the `createCalibrated` method channel call.
- The two-factory design (`ProductivityClassifier(Device)` + `ProductivityClassifier.withCalibration(Device, IndividualNfbData)`) is cleaner than NfbClassifier's optional parameter approach and makes the calibration path explicit.
- The private constructor branching (`calibration != null` → `createCalibrated`, else → `create`) correctly mirrors the proven NfbClassifier pattern.
- Stream decode lambdas for `calibrationProgress` and `calibrated` match PhysioClassifier exactly (`(map['progress'] as num).toDouble()` and `map['baselines'] as Uint8List`).
- `resetAccumulatedFatigue()` correctly identified as Productivity-unique and uses the already-defined `ClassifierMethods.resetAccumulatedFatigue` constant.
- Three clean phases with correct dependency ordering: channels → class → barrel export.
- Barrel export placement (after `physio_classifier.dart`) is alphabetically correct given the current export order.

PLAN_REVIEW_PASS
