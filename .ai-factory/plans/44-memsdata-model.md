# Plan: MemsData model

## Context

Add an immutable `MemsSample` Dart model that mirrors the native `clCMEMSTimedData` struct (accelerometer + gyroscope as `clCPoint3d` triplets, plus timestamp). This is the data class that the upcoming MEMSClassifier Dart API and native bridges will use to deliver MEMS stream events.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model + export

- [x] **Task 1: Create MemsSample model**
  Files: `lib/src/models/mems_data.dart`
  Create an `@immutable` class `MemsSample` following the same pattern as `EegData` in `lib/src/models/eeg_data.dart` (import `package:flutter/foundation.dart`, `@immutable` annotation, `const` constructor, `factory fromMap`).
  Fields (all required, non-nullable — MEMS data has no sentinel values):
    - `accelerometer` — Dart record type `({double x, double y, double z})`
    - `gyroscope` — Dart record type `({double x, double y, double z})`
    - `timestamp` — `DateTime`
  `factory MemsSample.fromMap(Map<Object?, Object?> map)`:
    - Read `ax`, `ay`, `az` as `num` → `.toDouble()` into `accelerometer` record.
    - Read `gx`, `gy`, `gz` as `num` → `.toDouble()` into `gyroscope` record.
    - Read `ts` as `int` → `DateTime.fromMillisecondsSinceEpoch(map['ts'] as int)`.
  Add a doc comment referencing `clCMEMSTimedData` and `clCPoint3d`.

- [x] **Task 2: Export MemsSample from barrel**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/models/mems_data.dart';` to the barrel file. Insert it alphabetically among the existing model exports (between `eeg_data.dart` and `emotions_states.dart` lines). Do NOT add any event channel constant — `NeiryEvents.memsData` already exists in `channel_names.dart`.
