## Plan Review: Productivity + Cardio Tab

**Files Referenced:** 6 (2 new providers, 1 new screen, 1 modified router + underlying API/model files)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** WARN — Architecture says "every stream must have a corresponding screen in the example app." The plan omits providers for `ProductivityClassifier.errorStream`, `ProductivityClassifier.individualNfbStream`, and the 6 nullable float baseline fields on `ProductivityIndexes`. However, every existing classifier provider in the codebase follows the same pattern of omitting error and trigger-only streams, so this is consistent with the established convention rather than a plan defect.
- **RULES.md:** WARN — File does not exist. No blocking rules to check.
- **ROADMAP.md:** WARN — The ROADMAP milestone description says `nfbCalibrationProvider` is a `StateNotifierProvider<IndividualNfbData?>`, but the actual implementation is `StateProvider<IndividualNfbData?>`. The plan correctly uses the actual codebase type. The ROADMAP description is stale, not the plan.

### Critical Issues

None.

### Verification Summary

**Task 1 (Productivity provider):**
- `useCalibrationToggleProvider` as `StateProvider<bool>` from `flutter_riverpod/legacy.dart` — matches the `StateProvider` pattern used by `physioBaselinesProvider` and `deviceIsStartedProvider`. Correct.
- `ProductivityClassifierNotifier` uses `ref.watch()` for both `nfbCalibrationProvider` and `useCalibrationToggleProvider` — deliberate divergence from `NfbClassifierNotifier` (which uses `ref.read`). This is correct: watching both means toggling the switch or updating calibration data automatically rebuilds the provider and recreates the classifier. The plan explicitly calls this out.
- All `ProductivityClassifier` API references verified against actual source:
  - `ProductivityClassifier(device)` and `.withCalibration(device, nfbData)` — both factory paths exist.
  - `startBaselineCalibration()`, `resetAccumulatedFatigue()`, `importBaselines(Uint8List)` — all signatures match.
  - `metricsStream` -> `Stream<ProductivityMetrics>`, `indexesStream` -> `Stream<ProductivityIndexes>`, `baselineStream` -> `Stream<ProductivityBaselines>`, `calibrationProgress` -> `Stream<double>`, `calibrated` -> `Stream<Uint8List>` — all getter names and return types match.
- `ref.onDispose` capturing local classifier instance — matches existing pattern in all other classifier notifiers.

**Task 2 (Cardio provider):**
- `CardioClassifierNotifier` follows the same gating + toggle pattern. Correct.
- All `CardioClassifier` API references verified:
  - `CardioClassifier(device)` and `.withCalibration(device, nfbData)` — both factory paths exist.
  - `stateStream` -> `Stream<CardioData>`, `ppgStream` -> `Stream<PpgData>`, `calibratedStream` -> `Stream<void>` — all match. Note: the plan correctly uses `calibratedStream` (not `calibrated`) for Cardio, matching the actual API.
- Imports `useCalibrationToggleProvider` from the productivity provider file — avoids duplication. Correct.

**Task 3 (Screen):**
- Screen structure as `ConsumerWidget` with `SingleChildScrollView` and `Column` — matches `ClassifiersScreen` pattern exactly.
- Calibration toggle: watches `nfbCalibrationProvider` + `useCalibrationToggleProvider`, disabled when `nfbData == null` — logic is correct.
- `ProductivityIndexes.relaxation` enum labels `['No Recommendation', 'Involvement', 'Relaxation', 'Slight Fatigue', 'Severe Fatigue', 'Chronic Fatigue']` — matches `clCProductivity_RecommendationValue` (0-5) from the model doc comment. Correct.
- `ProductivityIndexes.stress` enum labels `['No Stress', 'Anxiety', 'Stress']` — matches `clCProductivity_StressValue` (0-2). Correct.
- `ProductivityMetrics.fatigueGrowthRate` labels `['None', 'Low', 'Medium', 'High']` — matches `clCProductivity_FatigueGrowthRate` (0-3). Correct.
- `ProductivityMetrics.artifactsData` shown as byte count only — correct, the plan explicitly says "No hex dump."
- PPG display: `ppgData.values` is `List<double>`, `ppgData.timestamps` is `List<int>` — accessing `.last` with `.isNotEmpty` guard is correct for the `PpgData` model.
- `DateTime.fromMillisecondsSinceEpoch(ppgData.timestamps.last)` — correct, `timestamps` are epoch millis per model.
- `cardioCalibratedProvider` SnackBar via `ref.listen` — matches `_PhysioCard`'s `ref.listen(physioCalibratedProvider, ...)` pattern.
- `_MetricRow`, `_SignalQualityRow`, `_formatTime` defined locally as private widgets — correct, these are private in `classifiers_screen.dart` and cannot be imported.

**Task 4 (Router):**
- Current router has 4 `StatefulShellBranch` entries (indices 0-3: device, streams, classifiers, calibration).
- Inserting `/productivity` at index 3 and shifting calibration to index 4 — correct indexing.
- Adding a 5th `NavigationDestination` at the matching position — correct, branches and destinations must stay in sync.

### Positive Notes

- The plan is precise about which `ref` method to use (`watch` vs `read`) and explains why, demonstrating understanding of Riverpod rebuild semantics.
- All Dart API getter names, stream types, and method signatures match the actual source code exactly.
- The plan correctly identifies that `ProductivityClassifier.calibrated` returns `Stream<Uint8List>` (opaque blob) while `CardioClassifier.calibratedStream` returns `Stream<void>` (signal-only) — these are different APIs and the plan handles each correctly.
- Enum label arrays include bounds-checked fallback (`'Unknown ($value)'`), preventing runtime crashes on unexpected SDK values.
- Shared `useCalibrationToggleProvider` across both classifier providers avoids state duplication and is placed in the productivity provider file for clear ownership.

PLAN_REVIEW_PASS
