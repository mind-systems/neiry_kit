# Plan: Calibration Models

## Context

Add the calibration-related Dart models: `IndividualNfbData` (the only model with all non-nullable fields, a `toMap()`, and a nullable `timestamp`), two enums (`CalibrationStage`, `NfbCalibrationFailReason`), and the `CalibrationEvent` sealed class hierarchy that deserializes `{'type':'stage'/'done'}` maps from the native EventChannel into exhaustive Dart subtypes.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Enums

- [x] **Task 1: Create CalibrationStage enum**
  Files: `lib/src/models/calibration_stage.dart`
  Create an enhanced enum `CalibrationStage` with four values: `stage1(0)`, `stage2(1)`, `stage3(2)`, `stage4(3)`. These are **0-indexed** to match the C SDK's `clCIndividualNFBCalibrationStage` where `Stage_1 = 0`. Each carries `final int code`. Add a `static CalibrationStage fromCode(int code)` factory that iterates `values` and throws `ArgumentError` on unknown codes — same pattern as `NeiryErrorCode.fromCode` in `neiry_error_code.dart`. Add doc comments: stage1/3 = eyes closed 20s, stage2/4 = eyes open 20s.

- [x] **Task 2: Create NfbCalibrationFailReason enum**
  Files: `lib/src/models/nfb_calibration_fail_reason.dart`
  Create an enhanced enum `NfbCalibrationFailReason` with three values: `none(0)`, `tooManyArtifacts(1)`, `peakFrequencyAtBorder(2)`. Same `final int code` + `static fromCode(int)` pattern as Task 1. The `Nfb` prefix is required because this enum is specific to NFB calibration — physio and productivity classifiers have their own separate calibration with different failure modes. Add a file-level comment noting this mirrors `clCIndividualNFBCalibrationFailReason` codes from `CNFBCalibrator.h`.

### Phase 2: IndividualNfbData model

- [x] **Task 3: Create IndividualNfbData model** (depends on Task 2)
  Files: `lib/src/models/individual_nfb_data.dart`
  Create an `@immutable` class `IndividualNfbData` with `const` constructor. Fields mirror `clCIndividualNFBData` exactly:

  - `timestamp` — `DateTime?`, nullable (null when the C struct sends `-1`; the only field that can be absent)
  - `failReason` — `NfbCalibrationFailReason`, default `NfbCalibrationFailReason.none`
  - `individualFrequency` — `double`, default `10.0` (alpha peak center, Hz)
  - `individualPeakFrequency` — `double`, default `10.0` (legacy alias for `individualFrequency`)
  - `individualPeakFrequencyPower` — `double`, default `10.0` (power at peak, uV^2/Hz)
  - `individualPeakFrequencySuppression` — `double`, default `2.0` (closed/open eyes ratio)
  - `individualBandwidth` — `double`, default `6.0` (alpha band width, Hz)
  - `individualNormalizedPower` — `double`, default `0.5` (0-1 normalized)
  - `lowerFrequency` — `double`, default `7.0` (band lower bound, Hz)
  - `upperFrequency` — `double`, default `13.0` (band upper bound, Hz)

  Add convenience getter: `bool get isValid => failReason == NfbCalibrationFailReason.none;` — encapsulates the validity check so callers don't leak the `none` comparison.

  Add `factory IndividualNfbData.fromMap(Map<Object?, Object?> map)`:
  - Decode `timestamp`: if `map['ts']` is null or `(map['ts'] as int) < 0`, set to `null`; otherwise `DateTime.fromMillisecondsSinceEpoch(map['ts'] as int)`. This matches the existing timestamp pattern from `NfbUserState.fromMap` with the added null-check for the `-1` sentinel.
  - Cast numeric fields via `(map['key'] as num).toDouble()` (same `num` -> `double` safety pattern used elsewhere for `StandardMessageCodec` int/double ambiguity).
  - Decode `failReason` via `NfbCalibrationFailReason.fromCode(map['failReason'] as int)`.

  Add `Map<String, dynamic> toMap()` that serializes all fields to the same keys used in `fromMap`:
  - Encode `timestamp` as `'ts': timestamp?.millisecondsSinceEpoch ?? -1` (round-trip back to the C sentinel).
  - Encode `failReason` as `failReason.code`.
  - All double fields use their map key names.
  This is the only model that needs `toMap()` — required for `importCalibrationData()` MethodChannel args.

  Do NOT import `sentinel.dart` — this model has no sentinel float fields.

### Phase 3: CalibrationEvent sealed class

- [x] **Task 4: Create CalibrationEvent sealed class** (depends on Task 1, Task 3)
  Files: `lib/src/models/calibration_event.dart`
  Create a `sealed class CalibrationEvent` with two subtypes:
  - `CalibrationStageFinished` — holds `final CalibrationStage stage`. Constructor: `const CalibrationStageFinished({required this.stage})`.
  - `CalibrationCompleted` — holds `final IndividualNfbData data`. Constructor: `const CalibrationCompleted({required this.data})`.

  Add a static dispatch method `CalibrationEvent.deserialize(Map<Object?, Object?> map)` that dispatches by `map['type']`:
  - `'stage'` -> `CalibrationStageFinished(stage: CalibrationStage.fromCode(map['stage'] as int))`
  - `'done'` -> `CalibrationCompleted(data: IndividualNfbData.fromMap(map['data'] as Map<Object?, Object?>))`
  - else -> throws `ArgumentError`

  Name it `deserialize` (not `fromMap`) since the sealed class itself isn't a 1:1 struct mapping — it dispatches to different subtypes. This will be called by the Dart API layer when listening to the `NeiryEvents.nfbCalibration` EventChannel.

### Phase 4: Barrel export

- [x] **Task 5: Export new models from barrel** (depends on Tasks 1-4)
  Files: `lib/neiry_kit.dart`
  Add four export lines to `lib/neiry_kit.dart`:
  - `export 'src/models/calibration_stage.dart';`
  - `export 'src/models/nfb_calibration_fail_reason.dart';`
  - `export 'src/models/individual_nfb_data.dart';`
  - `export 'src/models/calibration_event.dart';`

  Place them after the existing model exports, grouped together. This makes all four types importable via `import 'package:neiry_kit/neiry_kit.dart';` for both the example app and `mind_mobile`.

## Commit Plan
- **Commit 1** (after tasks 1-5): "Add calibration models — IndividualNfbData, CalibrationStage, NfbCalibrationFailReason, CalibrationEvent sealed class"
