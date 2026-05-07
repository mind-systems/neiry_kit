# Plan: Productivity + Cardio tab

## Context
Add a 5th example app tab exercising `ProductivityClassifier` and `CardioClassifier` with a shared NFB calibration toggle, enum label rendering for productivity indexes, opaque artifacts blob display, and PPG last-value readout.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Providers

- [x] **Task 1: Productivity classifier provider with calibration toggle**
  Files: `example/lib/providers/productivity_classifier_provider.dart`
  Create a provider file following the pattern in `nfb_classifier_provider.dart` and `physio_classifier_provider.dart`:

  **`useCalibrationToggleProvider`** — `StateProvider<bool>((ref) => false)` (import from `flutter_riverpod/legacy.dart`). Shared toggle for both Productivity and Cardio classifiers; defined here, imported by cardio provider and the screen.

  **`ProductivityClassifierNotifier extends Notifier<ProductivityClassifier?>`**:
  - `build()` gates on `ref.watch(activeDeviceProvider)` + `ref.watch(deviceIsStartedProvider)` — returns `null` if either missing.
  - Reads `ref.watch(nfbCalibrationProvider)` and `ref.watch(useCalibrationToggleProvider)` — using `watch` (not `read`) so changing the toggle or calibration data automatically rebuilds the provider and recreates the classifier.
  - If `useCalibration && nfbData != null` calls `ProductivityClassifier.withCalibration(device, nfbData)`, otherwise `ProductivityClassifier(device)`.
  - `ref.onDispose(() { classifier.dispose(); })` capturing the local `classifier` variable.
  - Expose `startBaselineCalibration()` and `resetAccumulatedFatigue()` methods delegating to `state?`.
  - Expose `importBaselines(Uint8List data)` delegating to `state?.importBaselines(data)`.

  **Stream providers** (same pattern as `physioClassifierProvider` file):
  - `productivityMetricsProvider` — `StreamProvider<ProductivityMetrics>` watching `productivityClassifierProvider`, returning `classifier.metricsStream` or `Stream.empty()`.
  - `productivityIndexesProvider` — `StreamProvider<ProductivityIndexes>` from `classifier.indexesStream`.
  - `productivityBaselinesProvider` — `StreamProvider<ProductivityBaselines>` from `classifier.baselineStream`.
  - `productivityCalibrationProgressProvider` — `StreamProvider<double>` from `classifier.calibrationProgress`.
  - `productivityCalibratedProvider` — `StreamProvider<Uint8List>` from `classifier.calibrated`.

- [x] **Task 2: Cardio classifier provider with PPG stream**
  Files: `example/lib/providers/cardio_classifier_provider.dart`
  Create a provider file following the same pattern:

  **`CardioClassifierNotifier extends Notifier<CardioClassifier?>`**:
  - `build()` gates on `ref.watch(activeDeviceProvider)` + `ref.watch(deviceIsStartedProvider)`.
  - Reads `ref.watch(nfbCalibrationProvider)` and `ref.watch(useCalibrationToggleProvider)` (import from `productivity_classifier_provider.dart`).
  - If `useCalibration && nfbData != null` calls `CardioClassifier.withCalibration(device, nfbData)`, otherwise `CardioClassifier(device)`.
  - `ref.onDispose(() { classifier.dispose(); })` capturing the local variable.

  **Stream providers**:
  - `cardioStateProvider` — `StreamProvider<CardioData>` from `classifier.stateStream` or `Stream.empty()`.
  - `cardioPpgProvider` — `StreamProvider<PpgData>` from `classifier.ppgStream` or `Stream.empty()`.
  - `cardioCalibratedProvider` — `StreamProvider<void>` from `classifier.calibratedStream` or `Stream.empty()`.

### Phase 2: Screen + Router

- [x] **Task 3: Productivity + Cardio screen** (depends on Tasks 1, 2)
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  Create a screen following the structure of `classifiers_screen.dart` — a `ConsumerWidget` with `SingleChildScrollView` containing two cards in a `Column`.

  **Calibration toggle row** (above both cards):
  - Watch `nfbCalibrationProvider` and `useCalibrationToggleProvider`.
  - Render a `SwitchListTile` or `Row` with `Switch`:
    - `value: useCalibration && nfbData != null`
    - `onChanged: nfbData == null ? null : (val) { ref.read(useCalibrationToggleProvider.notifier).state = val; }`
    - Disabled (greyed out) when `nfbData == null`.
    - Show helper text: when `nfbData == null` display "Run calibration first to enable" in grey; when enabled display "Using individual NFB calibration".

  **`_ProductivityCard`** (private `ConsumerWidget`):
  - Watch `productivityClassifierProvider` — show "Waiting for device..." when `null`.
  - Watch `productivityIndexesProvider` — render enum labels, not raw ints:
    - `indexes.relaxation` as `clCProductivity_RecommendationValue` label. Define a const list: `['No Recommendation', 'Involvement', 'Relaxation', 'Slight Fatigue', 'Severe Fatigue', 'Chronic Fatigue']`. Look up by index with bounds check (fallback to `'Unknown ($value)'`).
    - `indexes.stress` as `clCProductivity_StressValue` label. Const list: `['No Stress', 'Anxiety', 'Stress']`. Same bounds-checked lookup.
    - `indexes.hasArtifacts` as a `_SignalQualityRow` (reuse pattern from `classifiers_screen.dart` or define locally).
  - Watch `productivityMetricsProvider` — render numeric fields:
    - Show `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue` using `_MetricRow` (label + `value?.toStringAsFixed(3) ?? '—'`).
    - `fatigueGrowthRate` as label: const list `['None', 'Low', 'Medium', 'High']`, lookup by int.
    - `artifactsData` — show `'Artifacts: ${data.length} bytes'` when non-null, `'Artifacts: none'` when null. No hex dump.
  - Watch `productivityCalibrationProgressProvider` — show `LinearProgressIndicator` while active (same pattern as `_PhysioCard`).
  - Show "Start Baseline Calibration" `ElevatedButton` calling `ref.read(productivityClassifierProvider.notifier).startBaselineCalibration()`.
  - Show "Reset Fatigue" `OutlinedButton` calling `ref.read(productivityClassifierProvider.notifier).resetAccumulatedFatigue()`.

  **`_CardioCard`** (private `ConsumerWidget`):
  - Watch `cardioClassifierProvider` — show "Waiting for device..." when `null`.
  - Watch `cardioStateProvider` — render fields:
    - When `metricsAvailable == false`: show "Calibrating... metrics not yet available" with `Opacity(opacity: 0.5)`.
    - When `metricsAvailable == true`: show `heartRate` (1 decimal), `stressIndex` (3 decimals), `kaplanIndex` (3 decimals).
    - Show boolean flags: `hasArtifacts`, `skinContact`, `motionArtifacts` as icon rows (green check / red error, same pattern as `_SignalQualityRow`).
  - Watch `cardioPpgProvider` — show PPG last value:
    - `ppgData.values.isNotEmpty ? ppgData.values.last.toStringAsFixed(1) : '—'`
    - Timestamp: `ppgData.timestamps.isNotEmpty ? DateTime.fromMillisecondsSinceEpoch(ppgData.timestamps.last).toLocal()` formatted as `HH:MM:SS` using the `_formatTime` helper.
    - Display as `'PPG: <value> @ <time>'` or `'PPG: —'`.
  - Listen to `cardioCalibratedProvider` — show `SnackBar('Cardio calibration complete')` when it emits (same `ref.listen` pattern as `_PhysioCard` does for `physioCalibratedProvider`).

  **Shared helpers** (private, in the same file):
  - `_MetricRow` — reuse the pattern from `classifiers_screen.dart`: `Row` with label in `SizedBox(width: 140)` and value `Text`.
  - `_SignalQualityRow` — same green/red icon pattern.
  - `_formatTime(DateTime)` — `HH:MM:SS` format.

- [x] **Task 4: Add Productivity+Cardio tab to router** (depends on Task 3)
  Files: `example/lib/router.dart`
  - Import `productivity_cardio_screen.dart`.
  - Add a 5th `StatefulShellBranch` with `GoRoute(path: '/productivity', builder: (_, _) => const ProductivityCardioScreen())` — insert between `/classifiers` and `/calibration` branches (index 3; calibration shifts to index 4).
  - Add a 5th `NavigationDestination` with `icon: Icon(Icons.trending_up)` and `label: 'Productivity'` — insert at the matching position in the `destinations` list.
