# Plan: PhysioClassifier

## Context

Implement the Dart API class `PhysioClassifier` that wraps the native `clCPhysiologicalStates` classifier. It follows the same pattern as the existing `NfbClassifier` but adds baseline calibration methods and calibration-related streams. All models (`PhysiologicalStatesValue`, `NfbUserState`) and most channel constants already exist.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel contract gap

- [x] **Task 1: Add missing EventChannel ID for physio individual NFB stream**
  Files: `lib/src/channel/channel_names.dart`
  The `NeiryEvents` class already has `physiologicalState`, `physiologicalCalibrationProgress`, and `physiologicalCalibrated`, but is missing an EventChannel for the individual NFB update stream (`clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent`). Add `physiologicalIndividualNfb` with value `'neiry_kit/events/physiologicalIndividualNfb'`. Place it right after `physiologicalCalibrated` to keep the physio group together.

### Phase 2: Dart API class

- [x] **Task 2: Create PhysioClassifier** (depends on Task 1)
  Files: `lib/src/api/classifiers/physio_classifier.dart`
  Create `PhysioClassifier` following the exact structural pattern of `NfbClassifier` (`lib/src/api/classifiers/nfb_classifier.dart`). Specifics:

  **MethodChannel:** `NeiryChannels.physiological` (`'neiry_kit/physiological'`).

  **Factory constructor:** `factory PhysioClassifier(Device device)` — guard on `device.isStarted`, delegate to private `PhysioClassifier._(serial)`. No calibration parameter in constructor (unlike NfbClassifier). The private constructor invokes `ClassifierMethods.create` with `{NeiryArgs.serial: _serial}` asynchronously, storing the future in `_nativeReady` and any error in `_createError` — identical to NfbClassifier's uncalibrated path.

  **Methods (new vs NfbClassifier):**
  - `Future<void> startBaselineCalibration()` — awaits `_nativeReady`, checks guards, invokes `ClassifierMethods.startBaselineCalibration` with `{NeiryArgs.serial: _serial}`.
  - `Future<void> importBaselines(Uint8List data)` — awaits `_nativeReady`, checks guards, invokes `ClassifierMethods.importBaselines` with `{NeiryArgs.serial: _serial, NeiryArgs.baselines: data}`.

  **Streams (4 total, all `late final` cached via the `_eventStream` helper):**
  - `Stream<PhysiologicalStatesValue> get stateStream` — EventChannel `NeiryEvents.physiologicalState`, decode via `PhysiologicalStatesValue.fromMap`.
  - `Stream<double> get calibrationProgress` — EventChannel `NeiryEvents.physiologicalCalibrationProgress`, decode `(raw as Map)['progress'] as double` (float 0.0–1.0).
  - `Stream<Uint8List> get calibrated` — EventChannel `NeiryEvents.physiologicalCalibrated`, decode `(raw as Map)['baselines'] as Uint8List` (opaque blob, fires once when calibration completes).
  - `Stream<NfbUserState> get individualNfbStream` — EventChannel `NeiryEvents.physiologicalIndividualNfb` (from Task 1), decode via `NfbUserState.fromMap`.

  **Guards:** same `_checkNotDisposed()` + `_checkReady()` pattern on all public getters and methods.

  **dispose():** identical to NfbClassifier — idempotent, awaits `_nativeReady`, skips native destroy if `_createError != null`, invokes `ClassifierMethods.dispose`.

  **Imports:** `dart:async`, `dart:typed_data` (for `Uint8List`), `package:flutter/services.dart`, `../device.dart`, `../../channel/channel_names.dart`, `../../models/physio_states.dart`, `../../models/nfb_user_state.dart`.

- [x] **Task 3: Export PhysioClassifier from barrel** (depends on Task 2)
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/classifiers/physio_classifier.dart';` to the barrel file. Place it after the existing `nfb_classifier.dart` export to keep classifier exports grouped.
