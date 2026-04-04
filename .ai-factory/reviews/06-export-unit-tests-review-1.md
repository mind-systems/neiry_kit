## Code Review: Export + Unit Tests

**Plan:** `06-export-unit-tests.md`
**Files changed:** `lib/neiry_kit.dart`, `test/models_test.dart`
**Test results:** 70/70 new tests pass, 48/48 existing tests pass (no regressions)

### Barrel export (`lib/neiry_kit.dart`)

- All 8 previously-exported symbols are preserved (reordered alphabetically). No regressions.
- All 8 missing model exports added: `DeviceInfo`, `NeiryError`, `NfbUserState`, `PhysiologicalStatesValue`, `EmotionsStates`, `ProductivityMetrics`, `ProductivityIndexes`, `ProductivityBaselines`.
- `internal/sentinel.dart` correctly excluded per architecture principle 4.
- Alphabetical sort is clean and consistent.

### Enum int mapping tests (Task 2)

- `NeiryErrorCode`: all 17 values individually asserted, round-trip via `fromCode`, unknown throws `ArgumentError`. Matches `neiry_error_code.dart` exactly.
- `CalibrationStage`: 4 values (0–3), round-trip, unknown throws. Matches `calibration_stage.dart`.
- `NfbCalibrationFailReason`: 3 values (0–2), round-trip, unknown throws. Matches `nfb_calibration_fail_reason.dart`.
- No overlap with `channel_names_test.dart` (which covers `NeiryDeviceType`, `NeiryDeviceMode`, `NeiryConnectionState`).

### Sentinel→null tests (Task 3)

- `NfbUserState`: tests `-1.0` (double), `0.5` (valid), and `-1` (int) sentinel variants. The int-vs-double case directly exercises the `(v as num).toDouble()` path in `orNull` — important because `StandardMessageCodec` may send `-1` as Dart `int`.
- `PhysiologicalStatesValue`: all 6 nullable fields sentinel → null, bool fields (`nfbArtifacts`, `cardioArtifacts`) preserved.
- `EmotionsStates`: int sentinel and valid-value variants, both correct.
- `ProductivityBaselines`: 6 nullable fields sentinel → null.
- `ProductivityIndexes`: nullable floats sentinel → null; int enums (`relaxation`, `stress`) and `hasArtifacts` bool always valid.
- `DeviceInfo`, `NeiryError`: no sentinel fields, straightforward `fromMap` construction verified.

### Uint8List?, CalibrationEvent, round-trip (Task 4)

- **`ProductivityMetrics.artifactsData`**: three cases tested correctly:
  1. `null` key → `null` field.
  2. `Uint8List(0)` → non-null `Uint8List` with length 0 (NOT coerced to null — matches the `fromMap` logic which only nulls when key is null).
  3. `Uint8List.fromList([1,2,3])` → preserved with correct bytes.
  - All 10 nullable double fields also verified sentinel → null in same group.

- **`CalibrationEvent.deserialize`**: dispatch by `type` key is correct:
  1. `'stage'` with `stage: 2` → `CalibrationStageFinished` with `CalibrationStage.stage3` (fromCode(2) = stage3).
  2. `'done'` with nested `IndividualNfbData` map → `CalibrationCompleted` with `isValid == true`.
  3. Unknown `'bogus'` → `ArgumentError`.

- **`IndividualNfbData` round-trip**: `fromMap → toMap → fromMap` tested with:
  1. All fields set (distinct values) — all 10 fields match after round-trip.
  2. `ts: -1` (null timestamp) — `fromMap` yields `null`, `toMap` encodes `-1`, second `fromMap` yields `null` again.
  - The `toMap()` returns `Map<String, dynamic>` which is a valid subtype of `fromMap`'s `Map<Object?, Object?>` parameter — no type error at runtime.

### Correctness check

- No type mismatches: all map key lookups and `as` casts match the actual `fromMap` implementations.
- No missing assertions: every nullable field in every model is verified.
- No platform dependencies: all tests are pure Dart, no mocking or platform channel calls.
- No regressions: existing `channel_names_test.dart` still passes.

### Critical issues

None.

### Suggestions

None.

REVIEW_PASS
