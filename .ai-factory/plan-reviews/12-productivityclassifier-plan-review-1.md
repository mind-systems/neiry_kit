## Code Review Summary

**Plan Reviewed:** `12-productivityclassifier.md`
**Files Affected:** 3 (channel_names.dart, productivity_classifier.dart [new], neiry_kit.dart)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — WARN: no issues. File path `lib/src/api/classifiers/productivity_classifier.dart` matches the folder structure. Dependency flow (api → channel + models) is respected. Barrel export pattern is followed.
- **RULES.md** — file does not exist, skipped.
- **ROADMAP.md** — WARN: plan aligns with the unchecked `ProductivityClassifier` milestone under "Dart API". No linkage gaps.

### Critical Issues

None.

### Suggestions

1. **Missing `errorStream` — unused `productivityError` event channel**
   `NeiryEvents.productivityError` already exists in `channel_names.dart` (line 61) but the plan does not expose it as a stream. Both `NfbClassifier` and `EmotionsClassifier` expose their corresponding error channels (`nfbError`, `emotionsError`) as `Stream<String> get errorStream`. The plan defines six streams but omits the error stream.

   If native bridges send error events on this channel, they will be silently dropped with no Dart listener. Either:
   - Add a seventh `_errorStream` / `errorStream` (2 lines of code, mirrors NfbClassifier/EmotionsClassifier), or
   - Explicitly document in the plan that the error channel is intentionally unused for Productivity (like PhysioClassifier, which has no corresponding error event channel at all).

   The asymmetry — having a channel defined but no consumer — is the concern. The spec at `04-dart-api-classifiers.md` doesn't list an error stream for Productivity, so the plan is spec-faithful, but the spec and channel contract are out of sync.

### Positive Notes

- The plan correctly identifies exactly which two EventChannel IDs are missing (`productivityBaselines`, `productivityIndividualNfb`) and leaves the four that already exist untouched — accurate codebase analysis.
- The two-factory design (`ProductivityClassifier(Device)` + `ProductivityClassifier.withCalibration(Device, IndividualNfbData)`) is a better API than NfbClassifier's optional-parameter approach — it makes the calibration data requirement explicit at the call site.
- The private constructor pattern with `_nativeReady` / `_createError` / `catchError` correctly reuses the proven NfbClassifier pattern for async native initialization.
- All referenced constants (`ClassifierMethods.create`, `ClassifierMethods.createCalibrated`, `ClassifierMethods.resetAccumulatedFatigue`, `NeiryArgs.serial`, `NeiryArgs.calibrationData`, `NeiryArgs.baselines`, `NeiryChannels.productivity`) exist in `channel_names.dart` — no missing contract pieces.
- Model classes (`ProductivityMetrics`, `ProductivityIndexes`, `ProductivityBaselines`, `NfbUserState`, `IndividualNfbData`) all exist with correct `fromMap` factories and `toMap` (for `IndividualNfbData`) — no new models needed.
- Import paths are accurate for the `classifiers/` subdirectory depth.
- The `resetAccumulatedFatigue()` method is correctly identified as Productivity-unique and uses the already-defined `ClassifierMethods.resetAccumulatedFatigue` constant.
- Barrel export placement (after `physio_classifier.dart`, alphabetical) is correct.
- Three clean phases with correct dependency ordering (channels → class → export).
