# Plan: ProductivityClassifier

## Context

Implement the `ProductivityClassifier` Dart API class — the fourth classifier in the plugin. It wraps the native `clCProductivity` lifecycle, exposes two factory constructors (plain and with individual NFB calibration data), calibration methods, fatigue reset, and seven typed streams (including an error stream matching the NfbClassifier/EmotionsClassifier pattern). All models (`ProductivityMetrics`, `ProductivityIndexes`, `ProductivityBaselines`) and most EventChannel IDs already exist; two missing event channel IDs and the classifier class itself are the only new artifacts.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel contract

- [x] **Task 1: Add missing EventChannel IDs for productivity streams**
  Files: `lib/src/channel/channel_names.dart`
  Two streams required by the spec have no corresponding EventChannel constant yet:
  - `productivityBaselines` (`'neiry_kit/events/productivityBaselines'`) — carries `ProductivityBaselines` during calibration
  - `productivityIndividualNfb` (`'neiry_kit/events/productivityIndividualNfb'`) — carries `NfbUserState` updates from the internal NFB classifier

  Add them inside the `NeiryEvents` class, grouped with the existing `productivityMetrics` / `productivityIndexes` / `productivityCalibrationProgress` / `productivityCalibrated` / `productivityError` constants. Follow the same `static const String` + single-line format used by the physiological equivalents (`physiologicalCalibrated`, `physiologicalIndividualNfb`).

### Phase 2: Dart API class

- [x] **Task 2: Create ProductivityClassifier** (depends on Task 1)
  Files: `lib/src/api/classifiers/productivity_classifier.dart`
  Create the file following the exact structural skeleton used by `PhysioClassifier` and `NfbClassifier`:

  **Imports:** `dart:async`, `dart:typed_data`, `package:flutter/services.dart`, relative imports for `device.dart`, `channel_names.dart`, `productivity_metrics.dart`, `productivity_indexes.dart`, `productivity_baselines.dart`, `nfb_user_state.dart`, `individual_nfb_data.dart`.

  **Two factory constructors** (combine the NfbClassifier calibration pattern with PhysioClassifier's plain-create pattern):
  - `factory ProductivityClassifier(Device device)` — checks `device.isStarted`, throws `StateError` if not, delegates to `ProductivityClassifier._(serial, calibration: null)`.
  - `factory ProductivityClassifier.withCalibration(Device device, IndividualNfbData nfbData)` — same guard, delegates to `ProductivityClassifier._(serial, calibration: nfbData)`.

  **Private constructor `ProductivityClassifier._(String serial, {IndividualNfbData? calibration})`:**
  - When `calibration != null`: invoke `ClassifierMethods.createCalibrated` with `{NeiryArgs.serial, NeiryArgs.calibrationData: calibration.toMap()}`.
  - When `calibration == null`: invoke `ClassifierMethods.create` with `{NeiryArgs.serial}`.
  - Capture future in `_nativeReady`, swallow errors into `_createError` — identical to `NfbClassifier._()`.

  **Static channel:** `static const _channel = MethodChannel(NeiryChannels.productivity)`.

  **Seven `late final` cached streams** (all built with the `_eventStream` helper):
  - `_baselineStream` → `EventChannel(NeiryEvents.productivityBaselines)`, decode with `ProductivityBaselines.fromMap`
  - `_indexesStream` → `EventChannel(NeiryEvents.productivityIndexes)`, decode with `ProductivityIndexes.fromMap`
  - `_metricsStream` → `EventChannel(NeiryEvents.productivityMetrics)`, decode with `ProductivityMetrics.fromMap`
  - `_calibrationProgress` → `EventChannel(NeiryEvents.productivityCalibrationProgress)`, decode: `(map) => (map['progress'] as num).toDouble()`
  - `_calibrated` → `EventChannel(NeiryEvents.productivityCalibrated)`, decode: `(map) => map['baselines'] as Uint8List`
  - `_individualNfbStream` → `EventChannel(NeiryEvents.productivityIndividualNfb)`, decode with `NfbUserState.fromMap`
  - `_errorStream` → `EventChannel(NeiryEvents.productivityError)`, decode: `(map) => map['message'] as String`. The `productivityError` channel constant already exists in `channel_names.dart`. This stream follows the identical pattern used by `NfbClassifier` and `EmotionsClassifier` for their error streams — without it, native error events on this channel would be silently dropped.

  **Public stream getters** — each calls `_checkNotDisposed()` then `_checkReady()` before returning the cached stream. Match PhysioClassifier's getter style and doc comments:
  - `Stream<ProductivityBaselines> get baselineStream`
  - `Stream<ProductivityIndexes> get indexesStream`
  - `Stream<ProductivityMetrics> get metricsStream`
  - `Stream<double> get calibrationProgress`
  - `Stream<Uint8List> get calibrated`
  - `Stream<NfbUserState> get individualNfbStream`
  - `Stream<String> get errorStream` — exposes native-side errors for this classifier, matching the pattern in NfbClassifier and EmotionsClassifier

  **Three methods** (follow PhysioClassifier's method pattern: `_checkNotDisposed()` → `await _nativeReady` → `_checkReady()` → `invokeMethod`):
  - `Future<void> startBaselineCalibration()` — invokes `ClassifierMethods.startBaselineCalibration` with `{NeiryArgs.serial}`.
  - `Future<void> importBaselines(Uint8List data)` — invokes `ClassifierMethods.importBaselines` with `{NeiryArgs.serial, NeiryArgs.baselines: data}`.
  - `Future<void> resetAccumulatedFatigue()` — invokes `ClassifierMethods.resetAccumulatedFatigue` with `{NeiryArgs.serial}`. This is unique to ProductivityClassifier.

  **Guards, helper, dispose** — copy verbatim from PhysioClassifier, updating class name in `StateError` messages to `'ProductivityClassifier'`.

  **Doc comment on the class** — follow the same `/// Wraps the native ... lifecycle` / `/// ## Usage` / `/// ## Lifecycle` structure from PhysioClassifier, adapted for productivity (mention two factory paths, baseline calibration, fatigue reset).

### Phase 3: Barrel export

- [x] **Task 3: Export ProductivityClassifier from barrel** (depends on Task 2)
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/classifiers/productivity_classifier.dart';` to the barrel file. Insert it alphabetically among the other classifier exports (after `physio_classifier.dart`).
