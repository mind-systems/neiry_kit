# Plan: PhysiologicalStatesBaselines model + PhysioClassifier fix

## Context

The `PhysioClassifier` currently treats baselines as opaque `Uint8List` bytes, but the native `clCPhysiologicalStates_Baselines` is a structured C struct with 6 named fields (`timestampMilli`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`). This milestone creates a typed `PhysiologicalStatesBaselines` Dart model with `fromMap`/`toMap`, updates `PhysioClassifier` streams and methods to use it instead of raw bytes, exports it from the barrel, and adds a round-trip unit test. iOS and Android bridges do not exist yet — the Dart-side contract change (expecting a map of 6 fields instead of bytes) will be picked up when those bridges are implemented in their respective milestones.

## Settings
- Testing: yes (one round-trip unit test required by milestone)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model

- [x] **Task 1: Create PhysiologicalStatesBaselines model**
  Files: `lib/src/models/physio_baselines.dart`
  Create an `@immutable` class `PhysiologicalStatesBaselines` following the `ProductivityBaselines` pattern (`lib/src/models/productivity_baselines.dart`), with these differences:
  - Fields: `timestamp: DateTime?`, `alpha: double?`, `beta: double?`, `alphaGravity: double?`, `betaGravity: double?`, `concentration: double?` — all nullable (including timestamp, unlike `ProductivityBaselines` where timestamp is non-nullable). Timestamp is nullable because the C struct uses `-1` sentinel for `timestampMilli`.
  - `const` constructor with all named optional parameters.
  - `factory PhysiologicalStatesBaselines.fromMap(Map<Object?, Object?> map)` — import `orNull` from `internal/sentinel.dart` for all double fields. For `timestamp`: read `map['ts']`, return `null` when the value is `null` or negative (sentinel `-1`), otherwise `DateTime.fromMillisecondsSinceEpoch(value as int)`.
  - `Map<String, dynamic> toMap()` — keys: `ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`. Null doubles emit `-1.0`, null timestamp emits `-1` (int). This reverse-sentinel is needed so the bridge receives the C-compatible sentinels when Dart fields are null.
  - Import `package:flutter/foundation.dart` for `@immutable`.

### Phase 2: PhysioClassifier API changes

- [x] **Task 2: Update PhysioClassifier.calibrated and importBaselines** (depends on Task 1)
  Files: `lib/src/api/classifiers/physio_classifier.dart`
  Four changes in this file:
  1. Add `import '../../models/physio_baselines.dart';`.
  2. Change the `_calibrated` field — type from `Stream<Uint8List>` to `Stream<PhysiologicalStatesBaselines>`, decoder from `(map) => map['baselines'] as Uint8List` to `PhysiologicalStatesBaselines.fromMap` (the bridge will emit baselines fields as the top-level map, not nested under a `baselines` key):
     ```dart
     late final Stream<PhysiologicalStatesBaselines> _calibrated = _eventStream(
       const EventChannel(NeiryEvents.physiologicalCalibrated),
       PhysiologicalStatesBaselines.fromMap,
     );
     ```
  3. Change `calibrated` getter return type from `Stream<Uint8List>` to `Stream<PhysiologicalStatesBaselines>`. Update its doc comment: replace "opaque baselines blob" with "structured baselines data (`PhysiologicalStatesBaselines`)" and change "Persist this blob" to "Persist this data (e.g. via `toMap()` + JSON)".
  4. Change `importBaselines(Uint8List data)` to `importBaselines(PhysiologicalStatesBaselines baselines)`. In the method body, change the argument value from `data` to `baselines.toMap()`:
     ```dart
     {NeiryArgs.serial: _serial, NeiryArgs.baselines: baselines.toMap()}
     ```
     Update the doc comment accordingly. Also update the class-level `Usage` doc comment: replace `savedBlob` with `savedBaselines` and `opaque blob, save for later` with `PhysiologicalStatesBaselines, save for later`.

### Phase 3: Export + test

- [x] **Task 3: Export from barrel** (depends on Task 1)
  Files: `lib/neiry_kit.dart`
  Add `export 'src/models/physio_baselines.dart';` — insert alphabetically between the `physio_states.dart` and `ppg_data.dart` export lines (between current lines 24 and 25).

- [x] **Task 4: Add fromMap/toMap round-trip unit test** (depends on Tasks 1, 3)
  Files: `test/models_test.dart`
  Add a new test group after the `PhysiologicalStatesValue` group (after line 186), following the existing test style. Group name: `PhysiologicalStatesBaselines.fromMap — round-trip + sentinels`. Three tests:
  - `all fields -1 / -1.0 → all null` — construct via `fromMap` with `{'ts': -1, 'alpha': -1.0, 'beta': -1.0, 'alphaGravity': -1.0, 'betaGravity': -1.0, 'concentration': -1.0}`, expect all 6 fields `isNull`.
  - `valid values → fromMap → toMap round-trip` — use `{'ts': 1000, 'alpha': 0.5, 'beta': 0.6, 'alphaGravity': 0.7, 'betaGravity': 0.8, 'concentration': 0.9}`, construct via `fromMap`, call `toMap()`, verify each key in the output map matches the input.
  - `mixed: some valid, some sentinel` — e.g. `{'ts': 2000, 'alpha': 0.5, 'beta': -1.0, 'alphaGravity': -1.0, 'betaGravity': 0.8, 'concentration': -1.0}`, verify `alpha` and `betaGravity` are populated, `beta`, `alphaGravity`, `concentration` are null, and `toMap()` re-emits `-1.0` for the null fields.
  - Import via the barrel `package:neiry_kit/neiry_kit.dart` (already imported in test file).

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add PhysiologicalStatesBaselines model and update PhysioClassifier to use typed baselines instead of raw bytes"
