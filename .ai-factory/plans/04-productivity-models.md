# Plan: Productivity models

## Context
Create three immutable Dart model classes that mirror the C SDK productivity structs (`clCProductivity_Metrics`, `clCProductivity_Indexes`, `clCProductivity_Baselines`), following the exact patterns established by `NfbUserState`, `PhysiologicalStatesValue`, and `EmotionsStates`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model classes

- [x] **Task 1: Create ProductivityBaselines model**
  Files: `lib/src/models/productivity_baselines.dart`
  Create `ProductivityBaselines` — mirrors `clCProductivity_Baselines` from `CProductivity.h`. Follow the `NfbUserState` pattern exactly: `@immutable` annotation, `import 'package:flutter/foundation.dart'` + `import 'internal/sentinel.dart'`, `const` constructor, `factory fromMap(Map<Object?, Object?> map)`.
  Fields:
  - `timestamp` (required `DateTime`) — decoded via `DateTime.fromMillisecondsSinceEpoch(map['ts'] as int)`
  - 6 nullable `double?` fields, all decoded via `orNull(map[key])`: `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration`
  Doc comment references `clCProductivity_Baselines` and explains sentinel-to-null behavior.

- [x] **Task 2: Create ProductivityIndexes model**
  Files: `lib/src/models/productivity_indexes.dart`
  Create `ProductivityIndexes` — mirrors `clCProductivity_Indexes`. Same pattern as Task 1 plus mixed field types like `PhysiologicalStatesValue` (which combines `double?` scores with `bool` flags).
  Fields:
  - `timestamp` (required `DateTime`) — same decoding pattern
  - `relaxation` (required `int`) — always valid, decoded as `map['relaxation'] as int`. Represents `clCProductivity_RecommendationValue` (NoRecommendation=0, Involvement=1, Relaxation=2, SlightFatigue=3, SevereFatigue=4, ChronicFatigue=5)
  - `stress` (required `int`) — always valid, decoded as `map['stress'] as int`. Represents `clCProductivity_StressValue` (NoStress=0, Anxiety=1, Stress=2)
  - 6 nullable `double?` fields via `orNull()`: `gravityBaseline`, `productivityBaseline`, `fatigueBaseline`, `reverseFatigueBaseline`, `relaxationBaseline`, `concentrationBaseline`
  - `hasArtifacts` (required `bool`) — always valid, decoded as `map['hasArtifacts'] as bool`
  Constructor order: `timestamp` and always-valid fields (`relaxation`, `stress`, `hasArtifacts`) as `required` named params first, then optional `double?` fields. Field declaration order in class body: `timestamp`, float fields, then int/bool fields — matching the `PhysiologicalStatesValue` pattern where scores precede flags.

- [x] **Task 3: Create ProductivityMetrics model**
  Files: `lib/src/models/productivity_metrics.dart`
  Create `ProductivityMetrics` — mirrors `clCProductivity_Metrics`. Most complex model: adds `Uint8List?` handling and an int enum field.
  Additional import: `import 'dart:typed_data';` for `Uint8List`.
  Fields:
  - `timestamp` (required `DateTime`) — same decoding pattern
  - 10 nullable `double?` fields via `orNull()`: `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`
  - `fatigueGrowthRate` (required `int`) — always valid, decoded as `map['fatigueGrowthRate'] as int`. Represents `clCProductivity_FatigueGrowthRate` (None=0, Low=1, Medium=2, High=3)
  - `artifactsData` (`Uint8List?`) — decoded from map: if `map['artifactsData']` is `null`, set to `null`; otherwise cast as `Uint8List`. The native bridge is responsible for sending `null` when `artifactsSize == 0` and a `Uint8List` copy otherwise (the Dart model does not see `artifactsSize`).
  Constructor order: `timestamp` and `fatigueGrowthRate` as `required`, then optional `double?` fields, then optional `artifactsData`.
