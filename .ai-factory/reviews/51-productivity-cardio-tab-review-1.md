# Code Review: Productivity + Cardio Tab

**Plan:** `.ai-factory/plans/51-productivity-cardio-tab.md`
**Files reviewed:** 4 (2 new providers, 1 new screen, 1 modified router)

## Files Reviewed

### `example/lib/providers/productivity_classifier_provider.dart` (new)
- `useCalibrationToggleProvider` — `StateProvider<bool>` from `legacy.dart`, matches `physioBaselinesProvider` / `deviceIsStartedProvider` pattern. Correct.
- `ProductivityClassifierNotifier` — gates on `activeDeviceProvider` + `deviceIsStartedProvider`, watches `nfbCalibrationProvider` + `useCalibrationToggleProvider` (intentionally `watch` not `read`, unlike NFB classifier — triggers rebuild on toggle/calibration change per plan). `ref.onDispose` captures local variable. Correct.
- Constructor delegation: `ProductivityClassifier.withCalibration(device, nfbData)` vs `ProductivityClassifier(device)` — matches API exactly.
- Stream providers: types match SDK API (`metricsStream → ProductivityMetrics`, `indexesStream → ProductivityIndexes`, `baselineStream → ProductivityBaselines`, `calibrationProgress → double`, `calibrated → Uint8List`).
- `importBaselines(Uint8List)` signature matches `ProductivityClassifier.importBaselines(Uint8List)`.
- `dart:typed_data` import present for `Uint8List`.

### `example/lib/providers/cardio_classifier_provider.dart` (new)
- Same notifier pattern as productivity. Constructor delegation matches `CardioClassifier` / `CardioClassifier.withCalibration` API.
- Stream types: `stateStream → CardioData`, `ppgStream → PpgData`, `calibratedStream → void`. All match.
- Imports `useCalibrationToggleProvider` from productivity provider file. No circular dependency.

### `example/lib/screens/productivity_cardio_screen.dart` (new)
- Structure follows `classifiers_screen.dart` pattern (ConsumerWidget, SingleChildScrollView, private card widgets).
- **Enum label tables:** `_recommendationLabels` (6 entries for 0–5), `_stressLabels` (3 entries for 0–2), `_fatigueGrowthLabels` (4 entries for 0–3) — all match SDK C enum ranges. `_labelFor` has bounds check with `'Unknown ($value)'` fallback.
- **`ProductivityIndexes.relaxation`/`.stress`:** both are `int` in the model, passed through `_labelFor`. Correct.
- **`ProductivityMetrics.fatigueGrowthRate`:** `int` in model, same lookup pattern. Correct.
- **`artifactsData`:** `Uint8List?`, displays `.length` when non-null, "none" when null. Correct.
- **Cardio metrics gate:** `data.metricsAvailable` check hides numeric fields when false, shows "Calibrating..." with opacity. Numeric fields (`heartRate`, `stressIndex`, `kaplanIndex`) are `double` (non-nullable in `CardioData`), passed to `_MetricRow(double?)` — valid subtype.
- **Skin contact inversion:** `_SignalQualityRow('Skin Contact', !data.skinContact)` — `skinContact=true` means good contact, so `!skinContact` shows red when no contact. Semantically correct.
- **PPG display:** guards `ppg.values.isNotEmpty` before accessing `.last`. `ppg.timestamps.last` accessed in same branch — safe because native bridge always populates both lists from the same sample loop with equal length.
- **`ref.listen(cardioCalibratedProvider, ...)`:** identical pattern to `_PhysioCard`'s `ref.listen(physioCalibratedProvider, ...)`. Fires on state change only, not initial state. Correct.
- **SwitchListTile:** `value: useCalibration && nfbData != null`, `onChanged: null` when `nfbData == null` (disabled). Correct.

### `example/lib/router.dart` (modified)
- 5th `StatefulShellBranch` added at index 3 (between classifiers and calibration). Matching `NavigationDestination` at same position. Import added. Correct.

## Lifecycle Safety

Verified `ref.onDispose` → `classifier.dispose()` ordering: Riverpod fires `onDispose` from previous build cycle before calling `build()` for the new cycle. `dispose()` is async but MethodChannel calls to the same channel (`NeiryChannels.productivity` / `NeiryChannels.cardio`) are serialized by the Flutter engine, so `dispose` completes before `create`. No race condition.

## Findings

None.

REVIEW_PASS
