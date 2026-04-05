# Plan: PhysiologicalStatesBaselines model + PhysioClassifier fix

## Context

The `PhysioClassifier` currently treats baselines as opaque `Uint8List` bytes, but the native `clCPhysiologicalStates_Baselines` is a structured C struct with 6 named fields. This milestone creates a proper `PhysiologicalStatesBaselines` Dart model, updates `PhysioClassifier` to use it instead of raw bytes, exports the new model, and adds a round-trip unit test. iOS and Android bridges do not exist yet — the contract change (map-of-6-fields instead of bytes) will be picked up when those bridges are implemented in their respective milestones.

## Settings
- Testing: yes (one round-trip unit test required by milestone)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model

- [ ] **Task 1: Create PhysiologicalStatesBaselines model**
  Files: `lib/src/models/physio_baselines.dart`
  Create an `@immutable` class `PhysiologicalStatesBaselines` following the exact pattern of `ProductivityBaselines` (`lib/src/models/productivity_baselines.dart`):
  - Fields: `timestamp: DateTime?`, `alpha: double?`, `beta: double?`, `alphaGravity: double?`, `betaGravity: double?`, `concentration: double?` — all nullable.
  - `const` constructor with named parameters (all optional).
  - `factory PhysiologicalStatesBaselines.fromMap(Map<Object?, Object?> map)` — use `orNull` from `internal/sentinel.dart` for all double fields. For `timestamp`: read `map['ts']` as `int?`, return `null` when the value is `null` or negative (sentinel `-1`), otherwise `DateTime.fromMillisecondsSinceEpoch(value)`. Import `package:flutter/foundation.dart` for `@immutable`.
  - `Map<String, dynamic> toMap()` — emit keys `ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`. Null doubles become `-1.0`, null timestamp becomes `-1` (int). This is the reverse of `fromMap` so the bridge receives sentinels when Dart fields are null.
  - Note: `timestamp` is `DateTime?` (unlike `ProductivityBaselines` where it's non-nullable `DateTime`) because the explore notes specify all fields nullable and the sentinel pattern maps `-1` to null.

### Phase 2: PhysioClassifier API changes

- [ ] **Task 2: Update PhysioClassifier.calibrated stream type** (depends on Task 1)
  Files: `lib/src/api/classifiers/physio_classifier.dart`
  - Add import for `../../models/physio_baselines.dart`.
  - Remove the `dart:typed_data` / `Uint8List` dependency (the `import 'package:flutter/services.dart'` already covers `Uint8List` via `dart:typed_data` re-export, but after this change `Uint8List` is no longer needed in the file at all — verify no remaining usage).
  - Change the `_calibrated` field from `Stream<Uint8List>` to `Stream<PhysiologicalStatesBaselines>`:
    ```dart
    late final Stream<PhysiologicalStatesBaselines> _calibrated = _eventStream(
      const EventChannel(NeiryEvents.physiologicalCalibrated),
      PhysiologicalStatesBaselines.fromMap,
    );
    ```
  - Update the `calibrated` getter return type from `Stream<Uint8List>` to `Stream<PhysiologicalStatesBaselines>`.
  - Update the doc comment on `calibrated` — replace "opaque baselines blob" with "structured baselines data" and mention `PhysiologicalStatesBaselines`.

- [ ] **Task 3: Update PhysioClassifier.importBaselines signature** (depends on Task 1)
  Files: `lib/src/api/classifiers/physio_classifier.dart`
  - Change `importBaselines(Uint8List data)` to `importBaselines(PhysiologicalStatesBaselines baselines)`.
  - In the method body, change the argument value from raw `data` to `baselines.toMap()`:
    ```dart
    await _channel.invokeMethod<void>(
      ClassifierMethods.importBaselines,
      {NeiryArgs.serial: _serial, NeiryArgs.baselines: baselines.toMap()},
    );
    ```
  - Update the doc comment — replace "saved [data] baselines" with "[baselines] data" and note it serializes via `toMap()` before passing to the bridge.
  - Update the class-level doc comment in the `Usage` section: change `importBaselines(savedBlob)` to `importBaselines(savedBaselines)` and change `opaque blob` to `PhysiologicalStatesBaselines`.

### Phase 3: Export + test

- [ ] **Task 4: Export PhysiologicalStatesBaselines from barrel**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/models/physio_baselines.dart';` — insert it alphabetically between the `physio_states.dart` and `ppg_data.dart` export lines.

- [ ] **Task 5: Add fromMap/toMap round-trip unit test**
  Files: `test/models_test.dart`
  Add a new test group `PhysiologicalStatesBaselines.fromMap — round-trip + sentinels` after the existing `PhysiologicalStatesValue` group (~line 189), following the exact style of the `ProductivityBaselines.fromMap` group (line 230):
  - Test 1: all fields `-1` / `-1.0` → all null (sentinel round-trip).
  - Test 2: valid values → `fromMap` → `toMap` → verify map matches input (true round-trip). Use a map like `{'ts': 1000, 'alpha': 0.5, 'beta': 0.6, 'alphaGravity': 0.7, 'betaGravity': 0.8, 'concentration': 0.9}`, construct via `fromMap`, call `toMap()`, and verify each key matches.
  - Test 3: mixed — some fields valid, some sentinel — verify nulls and non-nulls independently.
  - Import `PhysiologicalStatesBaselines` via the barrel `package:neiry_kit/neiry_kit.dart` (already imported in the test file).
