## Code Review: Productivity Models

**Plan:** `.ai-factory/plans/04-productivity-models.md`
**Files:** `productivity_baselines.dart`, `productivity_indexes.dart`, `productivity_metrics.dart`

### Static analysis

`flutter analyze` on all three files: **no issues found**.

### Field mapping — C header vs Dart models

Checked every field in `CProductivity.h` against the Dart implementations:

**`clCProductivity_Baselines` (line 70–78) → `ProductivityBaselines`**

| C field | C type | Dart field | Dart type | Decode |
|---|---|---|---|---|
| `timestampMilli` | int64_t, -1 | `timestamp` | DateTime | `fromMillisecondsSinceEpoch(map['ts'] as int)` |
| `gravity` | float, -1.F | `gravity` | double? | `orNull()` |
| `productivity` | float, -1.F | `productivity` | double? | `orNull()` |
| `fatigue` | float, -1.F | `fatigue` | double? | `orNull()` |
| `reverseFatigue` | float, -1.F | `reverseFatigue` | double? | `orNull()` |
| `relaxation` | float, -1.F | `relaxation` | double? | `orNull()` |
| `concentration` | float, -1.F | `concentration` | double? | `orNull()` |

Complete, no missing or extra fields.

**`clCProductivity_Indexes` (line 57–68) → `ProductivityIndexes`**

| C field | C type | Dart field | Dart type | Decode |
|---|---|---|---|---|
| `timestampMilli` | int64_t, -1 | `timestamp` | DateTime | `fromMillisecondsSinceEpoch(map['ts'] as int)` |
| `relaxation` | RecommendationValue enum | `relaxation` | int | `map['relaxation'] as int` |
| `stress` | StressValue enum | `stress` | int | `map['stress'] as int` |
| `gravityBaseline` | float, -1.F | `gravityBaseline` | double? | `orNull()` |
| `productivityBaseline` | float, -1.F | `productivityBaseline` | double? | `orNull()` |
| `fatigueBaseline` | float, -1.F | `fatigueBaseline` | double? | `orNull()` |
| `reverseFatigueBaseline` | float, -1.F | `reverseFatigueBaseline` | double? | `orNull()` |
| `relaxationBaseline` | float, -1.F | `relaxationBaseline` | double? | `orNull()` |
| `concentrationBaseline` | float, -1.F | `concentrationBaseline` | double? | `orNull()` |
| `hasArtifacts` | bool, false | `hasArtifacts` | bool | `map['hasArtifacts'] as bool` |

Complete, no missing or extra fields.

**`clCProductivity_Metrics` (line 25–40) → `ProductivityMetrics`**

| C field | C type | Dart field | Dart type | Decode |
|---|---|---|---|---|
| `timestampMilli` | int64_t, -1 | `timestamp` | DateTime | `fromMillisecondsSinceEpoch(map['ts'] as int)` |
| `fatigueScore` | float, -1.F | `fatigueScore` | double? | `orNull()` |
| `reverseFatigueScore` | float, -1.F | `reverseFatigueScore` | double? | `orNull()` |
| `gravityScore` | float, -1.F | `gravityScore` | double? | `orNull()` |
| `relaxationScore` | float, -1.F | `relaxationScore` | double? | `orNull()` |
| `concentrationScore` | float, -1.F | `concentrationScore` | double? | `orNull()` |
| `productivityScore` | float, -1.F | `productivityScore` | double? | `orNull()` |
| `currentValue` | float, -1.F | `currentValue` | double? | `orNull()` |
| `alpha` | float, -1.F | `alpha` | double? | `orNull()` |
| `productivityBaseline` | float, -1.F | `productivityBaseline` | double? | `orNull()` |
| `accumulatedFatigue` | float, -1.F | `accumulatedFatigue` | double? | `orNull()` |
| `fatigueGrowthRate` | FatigueGrowthRate enum | `fatigueGrowthRate` | int | `map['fatigueGrowthRate'] as int` |
| `artifactsData` | uint8_t* | `artifactsData` | Uint8List? | null-check then cast |
| `artifactsSize` | uint64_t | — | — | consumed by native bridge |

Complete, no missing or extra fields.

### Pattern consistency

Verified against `NfbUserState`, `PhysiologicalStatesValue`, and `EmotionsStates`:

- `@immutable` annotation with `import 'package:flutter/foundation.dart'` — all three files.
- `import 'internal/sentinel.dart'` — all three files.
- `const` constructor with `required` for always-valid fields, optional for sentinel fields — all three files.
- `factory fromMap(Map<Object?, Object?> map)` signature — all three files.
- Timestamp key `'ts'` decoded via `DateTime.fromMillisecondsSinceEpoch` — all three files.
- Sentinel floats via `orNull()` — all three files.
- Bool and int fields via direct cast — `ProductivityIndexes` and `ProductivityMetrics`.
- Field declaration order (timestamp, float scores, then int/bool flags) matches `PhysiologicalStatesValue`.
- Constructor order (required first, optional after) matches `PhysiologicalStatesValue`.

### `Uint8List` availability

The plan specified `import 'dart:typed_data'` for `ProductivityMetrics`, but the implementation omits it. `Uint8List` is available through Flutter's transitive exports from `package:flutter/foundation.dart`. The analyzer confirms no issue — this is valid.

### `@immutable` with `Uint8List?`

`Uint8List` elements are technically mutable, so an `@immutable`-annotated class holding one is not deeply immutable. This is standard Flutter practice (the analyzer does not flag it), and the model is conceptually immutable — the field reference itself cannot be reassigned. No action needed.

### Runtime considerations

- No migrations, no network calls, no state management — pure data classes.
- No risk of race conditions — all fields are `final`.
- `fromMap` casts will throw `TypeError` at runtime if the native bridge sends the wrong type — this is correct fail-fast behavior, matching all existing models.

### Verdict

All three models are correct, complete, and consistent with the established codebase patterns. No bugs, no security issues, no correctness problems found.

REVIEW_PASS
