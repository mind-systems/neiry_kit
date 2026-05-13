# Plan: Classifier stream providers

## Context
With `NeiryService` now owning all classifier lifecycle, collapse the six per-classifier `NotifierProvider` files into a single `classifier_stream_providers.dart` containing plain `StreamProvider`s that watch `neiryServiceProvider` and read off its multiplexer streams. Add the two missing calibration-progress streams (plus the missing Cardio PPG stream) to `NeiryService` so every classifier provider in the new file can be sourced from the service.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Extend NeiryService with missing classifier streams

- [x] **Task 1: Add calibration progress + cardio PPG streams to `NeiryService`**
  Files: `example/lib/services/neiry_service.dart`
  Three additions, each following the same broadcast-controller + fan-in pattern already established for `_physioController`, `_emotionsController`, etc. (see `neiry_service.dart:48-65`, `neiry_service.dart:146-203`, `neiry_service.dart:286-305`).

  1. **New broadcast controllers** — append next to the other multiplexer controllers (around `neiry_service.dart:62-65`):
     ```dart
     final _cardioPpgController = StreamController<PpgData>.broadcast();
     final _physioCalibrationProgressController =
         StreamController<double>.broadcast();
     final _productivityCalibrationProgressController =
         StreamController<double>.broadcast();
     ```

  2. **Fan-in subscriptions** — inside `connect()`, append three entries to the `_activeSubscriptions.addAll([...])` block (after the existing `_productivity!.metricsStream.listen(...)` entry near `neiry_service.dart:199-202`):
     ```dart
     _cardio!.ppgStream.listen(
       _cardioPpgController.add,
       onError: _cardioPpgController.addError,
     ),
     _physio!.calibrationProgress.listen(
       _physioCalibrationProgressController.add,
       onError: _physioCalibrationProgressController.addError,
     ),
     _productivity!.calibrationProgress.listen(
       _productivityCalibrationProgressController.add,
       onError: _productivityCalibrationProgressController.addError,
     ),
     ```
     Order inside the list does not affect correctness — all controllers are independent — but group the cardio PPG entry next to the existing `_cardio!.stateStream` line and the two calibration-progress entries near `_physio!.stateStream` / `_productivity!.metricsStream` so the file stays scannable by source.

  3. **Public getters** — append next to the other classifier stream getters (around `neiry_service.dart:338-353`):
     ```dart
     /// Emits PPG sample batches from the [CardioClassifier].
     Stream<PpgData> get cardioPpgStream => _cardioPpgController.stream;

     /// Emits Physio baseline-calibration progress (0.0–1.0).
     Stream<double> get physioCalibrationProgressStream =>
         _physioCalibrationProgressController.stream;

     /// Emits Productivity baseline-calibration progress (0.0–1.0).
     Stream<double> get productivityCalibrationProgressStream =>
         _productivityCalibrationProgressController.stream;
     ```

  4. **Close on dispose** — append three `await … .close();` lines inside `dispose()` (after `_productivityMetricsController.close()` at `neiry_service.dart:304`):
     ```dart
     await _cardioPpgController.close();
     await _physioCalibrationProgressController.close();
     await _productivityCalibrationProgressController.close();
     ```

  Notes:
  - The two `calibrationProgress` getters on `PhysioClassifier` and `ProductivityClassifier` already exist (see `lib/src/api/classifiers/physio_classifier.dart:135` and `lib/src/api/classifiers/productivity_classifier.dart:221`) and are safe to listen to before calibration starts — they are backed by long-lived event streams.
  - The new cardio PPG stream is required because the milestone calls for `cardioPpgProvider` sourced from `neiryService`, but `NeiryService` does not currently fan in `_cardio!.ppgStream`. Adding it here keeps the "all classifier data via NeiryService" contract intact.
  - Do not touch `disconnect()` — the controllers must stay open across reconnect, identical to every other multiplexer controller.
  - `PpgData` is already part of the `neiry_kit` barrel (used today by the legacy `cardioPpgProvider`); no new imports needed beyond the existing `package:neiry_kit/neiry_kit.dart`.

### Phase 2: Create the consolidated classifier stream providers file

- [x] **Task 2: Create `example/lib/providers/classifier_stream_providers.dart`** (depends on Task 1)
  Files: `example/lib/providers/classifier_stream_providers.dart` (new)
  Plain `StreamProvider`s — no `NotifierProvider`, no null-guarding on a classifier handle (the service controllers simply emit nothing pre-connect). Follow the pattern already used in `stream_providers.dart` after milestone #65: `ref.watch(neiryServiceProvider)` then return the relevant stream.

  Full file contents:
  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_riverpod/legacy.dart';
  import 'package:neiry_kit/neiry_kit.dart';
  import 'package:rxdart/rxdart.dart';

  import 'neiry_service_provider.dart';

  /// Emits [PhysiologicalStatesValue] from the active [PhysioClassifier].
  final physioStateProvider = StreamProvider<PhysiologicalStatesValue>((ref) {
    return ref.watch(neiryServiceProvider).physioStream;
  });

  /// Emits [EmotionsStates] from the active [EmotionsClassifier].
  final emotionsStateProvider = StreamProvider<EmotionsStates>((ref) {
    return ref.watch(neiryServiceProvider).emotionsStream;
  });

  /// Emits [CardioData] from the active [CardioClassifier].
  final cardioStateProvider = StreamProvider<CardioData>((ref) {
    return ref.watch(neiryServiceProvider).cardioStream;
  });

  /// Emits [PpgData] batches from the active [CardioClassifier].
  final cardioPpgProvider = StreamProvider<PpgData>((ref) {
    return ref.watch(neiryServiceProvider).cardioPpgStream;
  });

  /// Emits [MemsSample] batches throttled to ~10 Hz.
  final memsProvider = StreamProvider<List<MemsSample>>((ref) {
    return ref
        .watch(neiryServiceProvider)
        .memsStream
        .throttleTime(const Duration(milliseconds: 100));
  });

  /// Emits [NfbUserState] from the active [NfbClassifier].
  final nfbStateProvider = StreamProvider<NfbUserState>((ref) {
    return ref.watch(neiryServiceProvider).nfbStream;
  });

  /// Emits [ProductivityIndexes] from the active [ProductivityClassifier].
  final productivityIndexesProvider = StreamProvider<ProductivityIndexes>((ref) {
    return ref.watch(neiryServiceProvider).productivityIndexesStream;
  });

  /// Emits [ProductivityMetrics] from the active [ProductivityClassifier].
  final productivityMetricsProvider = StreamProvider<ProductivityMetrics>((ref) {
    return ref.watch(neiryServiceProvider).productivityMetricsStream;
  });

  /// Emits Physio baseline-calibration progress (0.0–1.0).
  final physioCalibrationProgressProvider = StreamProvider<double>((ref) {
    return ref.watch(neiryServiceProvider).physioCalibrationProgressStream;
  });

  /// Emits Productivity baseline-calibration progress (0.0–1.0).
  final productivityCalibrationProgressProvider = StreamProvider<double>((ref) {
    return ref.watch(neiryServiceProvider).productivityCalibrationProgressStream;
  });

  /// Holds the last calibrated or imported [PhysiologicalStatesBaselines].
  ///
  /// Written by `PhysioActionsNotifier` in the next milestone; consumed by the
  /// Export Baselines button on the Classifiers screen.
  final physioBaselinesProvider =
      StateProvider<PhysiologicalStatesBaselines?>((ref) => null);
  ```

  Notes:
  - Use `ref.watch` (not `read`) for the `neiryServiceProvider` lookup, matching the convention established in `stream_providers.dart` (milestone #65). The service identity does not change in practice, but `watch` keeps the provider graph honest and parallels the surrounding code.
  - `package:flutter_riverpod/legacy.dart` is needed for `StateProvider` (same pattern used in `physio_classifier_provider.dart:2` and elsewhere in `example/lib/providers/`).
  - `package:rxdart/rxdart.dart` is needed for the `.throttleTime(...)` extension on `memsStream` — same throttle window as the legacy `memsProvider` (`mems_classifier_provider.dart:65`).
  - **Intentionally omitted** providers from the legacy files (handled in subsequent milestones, not in scope here):
    - `physioCalibratedProvider`, `productivityCalibratedProvider`, `cardioCalibratedProvider`, `productivityBaselinesProvider`, `useCalibrationToggleProvider`, `useMemsCalibrationToggleProvider`, and every `*ClassifierProvider` / `*ClassifierNotifier`. The milestone description lists exactly the providers above; do not add others.
  - No throttling on EEG/PSD/battery — those stay in `stream_providers.dart`. This file is classifier streams only.

### Phase 3: Delete legacy classifier provider files

- [x] **Task 3: Delete the six legacy classifier provider files** (depends on Task 2)
  Files (delete outright):
  - `example/lib/providers/cardio_classifier_provider.dart`
  - `example/lib/providers/mems_classifier_provider.dart`
  - `example/lib/providers/productivity_classifier_provider.dart`
  - `example/lib/providers/emotions_classifier_provider.dart`
  - `example/lib/providers/nfb_classifier_provider.dart`
  - `example/lib/providers/physio_classifier_provider.dart`

  Use `rm` (or your IDE's delete) on each path. Do **not** edit any screen, notifier, or other consumer in this milestone — those migrations are explicitly assigned to roadmap milestones #91 (`PhysioActionsNotifier` / `ProductivityActionsNotifier`), #92 (`device_screen` + `streams_screen` + `main.dart`), and #93 (`classifiers_screen` + `mems_screen` + `productivity_cardio_screen` + `calibration_screen`).

  Expected `flutter analyze` errors after deletion — these are acceptable and must NOT be patched in this milestone:
  - `example/lib/screens/classifiers_screen.dart` — references `emotionsClassifierProvider`, `physioClassifierProvider`, `physioCalibratedProvider`.
  - `example/lib/screens/productivity_cardio_screen.dart` — references `useCalibrationToggleProvider`, `productivityClassifierProvider`, `cardioClassifierProvider`, `cardioCalibratedProvider`.
  - `example/lib/screens/mems_screen.dart` — references `useMemsCalibrationToggleProvider`, `memsClassifierProvider`.
  - `example/lib/screens/calibration_screen.dart` — references `nfbClassifierProvider`.

  Run `flutter analyze` in `example/` after deletion only to confirm the error set is confined to those four screen files. Any other broken import is an unexpected consumer and must be investigated before declaring the milestone done. Identifiers that survive into the new `classifier_stream_providers.dart` (`physioBaselinesProvider`, `physioStateProvider`, `emotionsStateProvider`, `cardioStateProvider`, `cardioPpgProvider`, `memsProvider`, `nfbStateProvider`, `productivityIndexesProvider`, `productivityMetricsProvider`, `physioCalibrationProgressProvider`, `productivityCalibrationProgressProvider`) will resolve once the screens update their imports in milestones #91–#93 — they do **not** need an import-path patch in this milestone because the screens are already broken by the missing classifier-provider identifiers.

## Commit Plan
- **Commit 1** (after task 1): "Add cardio PPG and calibration progress streams to NeiryService"
- **Commit 2** (after tasks 2–3): "Replace per-classifier providers with consolidated classifier_stream_providers"
