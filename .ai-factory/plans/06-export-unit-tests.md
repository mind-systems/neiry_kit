# Plan: Export + Unit Tests

## Context
Complete the Dart models milestone by exporting all 8 remaining model classes from the barrel file and adding unit tests that verify sentinel→null conversion, `Uint8List?` handling, enum int mappings, `CalibrationEvent` dispatch, and `IndividualNfbData` round-trip serialization.

## Settings
- Testing: yes (this milestone is specifically about tests)
- Logging: none
- Docs: no

## Tasks

### Phase 1: Barrel export

- [x] **Task 1: Export missing models from `lib/neiry_kit.dart`**
  Files: `lib/neiry_kit.dart`
  Add 8 export statements for the models that are currently in `lib/src/models/` but not re-exported from the barrel. The missing exports are:
  - `src/models/device_info.dart`
  - `src/models/neiry_error.dart`
  - `src/models/nfb_user_state.dart`
  - `src/models/physio_states.dart`
  - `src/models/emotions_states.dart`
  - `src/models/productivity_metrics.dart`
  - `src/models/productivity_indexes.dart`
  - `src/models/productivity_baselines.dart`

  Place them after the existing model exports (line 8), keeping alphabetical or logical grouping consistent with the existing style. Do NOT export `src/models/internal/sentinel.dart` — it is internal-only per architecture rules.

### Phase 2: Unit tests

- [x] **Task 2: Enum int mapping and round-trip tests** (depends on Task 1)
  Files: `test/models_test.dart`
  Create a new test file. Import `package:neiry_kit/neiry_kit.dart` and `package:flutter_test/flutter_test.dart`. Follow the style established in `test/channel_names_test.dart` (grouped tests, comment section dividers).

  Add groups for enums that were NOT covered in `channel_names_test.dart`:
  - **`NeiryErrorCode` int codes match SDK** — assert each of the 17 values individually (e.g. `ok == 0`, `failedToConnect == 1`, ... `unknown == 255`).
  - **`NeiryErrorCode.fromCode` round-trips** — iterate all values, verify `fromCode(v.code) == v`.
  - **`NeiryErrorCode.fromCode` throws on unknown** — verify code `999` throws `ArgumentError`.
  - **`CalibrationStage` int codes match SDK** — 4 values: `stage1 == 0`, `stage2 == 1`, `stage3 == 2`, `stage4 == 3`.
  - **`CalibrationStage.fromCode` round-trips** — iterate all values.
  - **`CalibrationStage.fromCode` throws on unknown** — code `99`.
  - **`NfbCalibrationFailReason` int codes match SDK** — 3 values: `none == 0`, `tooManyArtifacts == 1`, `peakFrequencyAtBorder == 2`.
  - **`NfbCalibrationFailReason.fromCode` round-trips** — iterate all values.
  - **`NfbCalibrationFailReason.fromCode` throws on unknown** — code `99`.

- [x] **Task 3: Sentinel→null and model fromMap tests** (depends on Task 2)
  Files: `test/models_test.dart`
  Append groups to the same test file:

  - **`NfbUserState.fromMap` — sentinel fields become null** — pass a map where all band fields are `-1.0` and verify all are `null`. Pass a second map where all bands are valid positive values (e.g. `0.5`) and verify they come through. Also test with int sentinel `-1` (the `StandardMessageCodec` int-vs-double case).
  - **`PhysiologicalStatesValue.fromMap` — sentinel fields become null** — map with all 6 nullable fields as `-1.0` → all `null`; bool fields (`nfbArtifacts`, `cardioArtifacts`) are always present as `true`/`false`.
  - **`EmotionsStates.fromMap` — sentinel fields become null** — map with all 5 fields as `-1` (int sentinel) → all `null`; map with valid values → all populated.
  - **`ProductivityBaselines.fromMap` — sentinel fields** — same pattern, 6 nullable fields.
  - **`ProductivityIndexes.fromMap` — sentinel + always-valid fields** — nullable float fields sentinel → `null`; `relaxation` (int), `stress` (int), `hasArtifacts` (bool) always valid.
  - **`DeviceInfo.fromMap` — no sentinel fields** — simple construction check with `serial`, `name`, `type` (int → `NeiryDeviceType`).
  - **`NeiryError.fromMap`** — verify `message`, `success`, `code` (int → `NeiryErrorCode`) round-trip.

- [x] **Task 4: Uint8List?, CalibrationEvent dispatch, IndividualNfbData round-trip** (depends on Task 2)
  Files: `test/models_test.dart`
  Append groups:

  - **`ProductivityMetrics.fromMap` — `Uint8List?` size=0 case** — three sub-tests:
    1. Map with `artifactsData: null` → field is `null`.
    2. Map with `artifactsData: Uint8List(0)` (empty, length 0) — verify the field is a `Uint8List` with length 0 (NOT null — the `fromMap` takes it as-is; null only when the key itself is null).
    3. Map with `artifactsData: Uint8List.fromList([1, 2, 3])` → field has length 3 with correct bytes.
    Also verify sentinel→null on the 10 nullable double fields and `fatigueGrowthRate` as int.

  - **`CalibrationEvent.deserialize` — dispatch by `type` key** — three sub-tests:
    1. `{'type': 'stage', 'stage': 2}` → produces `CalibrationStageFinished` with `stage == CalibrationStage.stage3`.
    2. `{'type': 'done', 'data': <valid IndividualNfbData map>}` → produces `CalibrationCompleted`, verify `data.isValid` is `true`.
    3. `{'type': 'bogus'}` → throws `ArgumentError`.

  - **`IndividualNfbData.fromMap` → `toMap` → `fromMap` round-trip** — two sub-tests:
    1. Construct a map with all fields set (including positive `ts`, `failReason: 0`, all 8 numeric fields as distinct values); call `fromMap`, then `toMap`, then `fromMap` again; verify all fields match the original.
    2. Construct a map with `ts: -1` (null timestamp); verify `fromMap` produces `timestamp == null`, then `toMap` encodes it back as `ts: -1`, then `fromMap` again yields `timestamp == null`.
