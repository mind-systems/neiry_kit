# Dart Models — C Struct Mapping

**Date:** 2026-04-03
**Source:** SDK docs — struct pages, _c_device_info_8h, architecture guidelines

## Key Findings

- 9 Dart model classes needed, all `@immutable` with `fromMap` factories; `IndividualNfbData` also requires `toMap()` — needed for `importCalibrationData()` MethodChannel args and example Export
- Only `clCIndividualNFBData` has NO sentinel fields — all floats have meaningful defaults
- `clCPhysiologicalStates_Value` includes a `none` field (float, -1 sentinel) representing "no dominant state"
- `clCProductivity_Metrics` includes binary artifact data (`uint8_t*` + size) → `Uint8List?`
- `clCError` → `NeiryError` — not a data model, used for exception construction; code is enum, all fields always valid

## Details

### Model Classes Summary

| C Struct | Dart Class | File | Sentinel Fields |
|---|---|---|---|
| `clCDeviceInfo` | `DeviceInfo` | `device_info.dart` | none |
| `clCNFB_UserState` | `NfbUserState` | `nfb_user_state.dart` | delta, theta, alpha, smr, beta |
| `clCPhysiologicalStates_Value` | `PhysiologicalStatesValue` | `physio_states.dart` | relaxation, fatigue, none, concentration, involvement, stress |
| `clCEmotions_States` | `EmotionsStates` | `emotions_states.dart` | attention, relaxation, cognitiveLoad, cognitiveControl, selfControl |
| `clCProductivity_Metrics` | `ProductivityMetrics` | `productivity_metrics.dart` | 11 float fields; artifactsData via size |
| `clCProductivity_Indexes` | `ProductivityIndexes` | `productivity_indexes.dart` | 6 float baselines; enums/bool always valid |
| `clCProductivity_Baselines` | `ProductivityBaselines` | `productivity_baselines.dart` | all 6 float fields |
| `clCIndividualNFBData` | `IndividualNfbData` | `individual_nfb_data.dart` | none (defaults: 10.F, 7.F, 13.F, etc.) |
| `clCError` | `NeiryError` | `error.dart` | none |

### Sentinel-to-null helper (shared codec pattern)

```dart
double? orNull(Object? v) => v == null || (v as double) < 0 ? null : v;
```

### Timestamp pattern

```dart
DateTime.fromMillisecondsSinceEpoch(map['ts'] as int)
```

### clCProductivity_Metrics — artifact fields

- `artifactsData` → `Uint8List?` (null if size == 0)
- `fatigueGrowthRate` → `int` (enum: None=0, Low=1, Medium=2, High=3), always valid

### clCProductivity_Indexes — enum fields

- `relaxation` → `int` (clCProductivity_RecommendationValue: NoRec=0...ChronicFatigue=5), always valid
- `stress` → `int` (clCProductivity_StressValue: NoStress=0, Anxiety=1, Stress=2), always valid
- `hasArtifacts` → `bool`, always valid

### clCIndividualNFBData — all fields non-nullable

- `individualFrequency` default 10.F (Hz)
- `individualPeakFrequencyPower` default 10.F
- `individualPeakFrequencySuppression` default 2.F (ratio closed/open eyes)
- `individualBandwidth` default 6.F (Hz)
- `individualNormalizedPower` default 0.5F
- `lowerFrequency` default 7.F, `upperFrequency` default 13.F
- `failReason` → enum `NfbCalibrationFailReason`: None=0, TooManyArtifacts=1, PeakFrequencyAtBorder=2

### Additional models not in C structs (pure Dart constructs)

- `CalibrationStage` enum — stage1 (closed, 20s), stage2 (open, 20s), stage3 (closed, 20s), stage4 (open, 20s)
- `NfbCalibrationFailReason` enum — none=0, tooManyArtifacts=1, peakFrequencyAtBorder=2
- `CalibrationEvent` — **sealed class**, replaces `CalibrationProgress`. Native side sends two event types over one EventChannel:
  - `{'type': 'stage', 'stage': 2}` → `CalibrationStageFinished(stage: CalibrationStage)`
  - `{'type': 'done', 'data': {...}}` → `CalibrationCompleted(data: IndividualNfbData)`
  - Dart side deserializes the map and constructs the correct subtype. `CalibrationEvent` itself has no `fromMap` — only `IndividualNfbData` does.
  - Rationale: one subscriber instead of two, exhaustive `switch` via compiler, extensible without breaking change.
- `NeiryException` — base exception; subclasses: `BluetoothDisabledException`, `DeviceNotConnectedException`, `CalibrationRequiredException`
- `NeiryErrorCode` enum — 16 values mapped from `clCError_Code`
