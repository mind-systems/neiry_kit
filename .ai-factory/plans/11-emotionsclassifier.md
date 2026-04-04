# Plan: EmotionsClassifier

## Context

Add the `EmotionsClassifier` Dart API class — the simplest classifier in the plugin. It wraps the native `clCEmotions` lifecycle, exposes `stateStream` (continuous `EmotionsStates`) and `errorStream`, requires no calibration, and follows the identical structural pattern already established by `NfbClassifier` and `PhysioClassifier`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Implementation

- [x] **Task 1: Create EmotionsClassifier class**
  Files: `lib/src/api/classifiers/emotions_classifier.dart`
  Create the file following the exact pattern from `lib/src/api/classifiers/nfb_classifier.dart`. Specifically:
  - `static const _channel = MethodChannel(NeiryChannels.emotions)`
  - Factory constructor `EmotionsClassifier(Device device)` that guards on `device.isStarted` (throws `StateError` if not started), delegates to private `EmotionsClassifier._(serial)`.
  - Private named constructor fires `_channel.invokeMethod<void>(ClassifierMethods.create, {NeiryArgs.serial: _serial})` and stores the future in `late final Future<void> _nativeReady`; catches errors into `Object? _createError`.
  - No calibration variant — emotions has no calibration path (unlike NFB which has an optional `IndividualNfbData`).
  - Two `late final` cached streams using the same `_eventStream<T>` helper pattern:
    - `_stateStream` via `EventChannel(NeiryEvents.emotionsState)`, decoded with `EmotionsStates.fromMap`
    - `_errorStream` via `EventChannel(NeiryEvents.emotionsError)`, decoded as `(map) => map['message'] as String`
  - Public getters `stateStream` and `errorStream` guarded by `_checkNotDisposed()` + `_checkReady()`.
  - `dispose()` method: idempotent (`if (_disposed) return`), awaits `_nativeReady`, skips native destroy if `_createError != null`, otherwise calls `ClassifierMethods.dispose` with serial.
  - Import `EmotionsStates` from `../../models/emotions_states.dart` (model already exists with `fromMap` factory, five nullable double fields + timestamp).
  - All channel constants already exist: `NeiryChannels.emotions`, `NeiryEvents.emotionsState`, `NeiryEvents.emotionsError`.

- [x] **Task 2: Export EmotionsClassifier from barrel file**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/classifiers/emotions_classifier.dart';` after the existing `physio_classifier.dart` export line (line 2). Keep alphabetical order among classifiers: nfb, physio would be joined by emotions — place it before nfb to maintain alphabetical order (`emotions` < `nfb` < `physio`), so insert as the new line 1.
