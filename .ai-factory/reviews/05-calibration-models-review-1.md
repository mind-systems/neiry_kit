## Code Review: Calibration Models

**Plan:** `.ai-factory/plans/05-calibration-models.md`
**Files Changed:** 4 new files + 1 barrel update
**Analysis:** `flutter analyze` — 0 issues

### Verification Against C SDK Header

Checked every field in `official/iOS/CapsuleClient.framework/Headers/CNFBCalibrator.h`.

**`CalibrationStage` codes vs `clCIndividualNFBCalibrationStage`:**

| C enum | Dart enum | Code | Match |
|---|---|---|---|
| `clCIndividualNFBCalibrationStage_1` | `stage1` | 0 | ✅ |
| `clCIndividualNFBCalibrationStage_2` | `stage2` | 1 | ✅ |
| `clCIndividualNFBCalibrationStage_3` | `stage3` | 2 | ✅ |
| `clCIndividualNFBCalibrationStage_4` | `stage4` | 3 | ✅ |

**`NfbCalibrationFailReason` codes vs `clCIndividualNFBCalibrationFailReason`:**

| C enum | Dart enum | Code | Match |
|---|---|---|---|
| `..._None` | `none` | 0 | ✅ |
| `..._TooManyArtifacts` | `tooManyArtifacts` | 1 | ✅ |
| `..._PeakIsABorder` | `peakFrequencyAtBorder` | 2 | ✅ |

**`IndividualNfbData` fields vs `clCIndividualNFBData`:**

| C struct field | Dart field | Type | Default | Match |
|---|---|---|---|---|
| `int64_t timestampMilli = -1` | `timestamp` | `DateTime?` (null when -1) | — | ✅ |
| `clCIndividualNFBCalibrationFailReason failReason` | `failReason` | `NfbCalibrationFailReason` | `.none` | ✅ |
| `float individualFrequency = 10.F` | `individualFrequency` | `double` | `10.0` | ✅ |
| `float individualPeakFrequency = 10.F` | `individualPeakFrequency` | `double` | `10.0` | ✅ |
| `float individualPeakFrequencyPower = 10.F` | `individualPeakFrequencyPower` | `double` | `10.0` | ✅ |
| `float individualPeakFrequencySuppression = 2.F` | `individualPeakFrequencySuppression` | `double` | `2.0` | ✅ |
| `float individualBandwidth = 6.F` | `individualBandwidth` | `double` | `6.0` | ✅ |
| `float individualNormalizedPower = 0.5F` | `individualNormalizedPower` | `double` | `0.5` | ✅ |
| `float lowerFrequency = 7.F` | `lowerFrequency` | `double` | `7.0` | ✅ |
| `float upperFrequency = 13.F` | `upperFrequency` | `double` | `13.0` | ✅ |

All 10 fields present with correct types and defaults. No missing or extra fields.

### Plan Review Fixes Verified

All 7 issues from the plan review are correctly addressed in the implementation:

1. **CalibrationStage 0-indexed** — `stage1(0)` through `stage4(3)`. ✅
2. **`timestamp` field present** — `DateTime?`, null when native sends -1, sentinel-decoded in `fromMap`, round-tripped as `-1` in `toMap`. ✅
3. **`individualPeakFrequency` field present** — `double`, default `10.0`, included in both `fromMap` and `toMap`. ✅
4. **`NfbCalibrationFailReason` naming** — file `nfb_calibration_fail_reason.dart`, class `NfbCalibrationFailReason`, all references consistent. ✅
5. **EventChannel reference** — doc comment correctly references `NeiryEvents.nfbCalibration`. ✅
6. **`isValid` getter** — `bool get isValid => failReason == NfbCalibrationFailReason.none;` present on `IndividualNfbData`. ✅
7. **`CalibrationEvent.deserialize` pinned** — static method, clear dispatch, documented. ✅

### File-by-File Analysis

**`calibration_stage.dart`** — Clean enhanced enum. `fromCode` follows `NeiryErrorCode.fromCode` pattern exactly. Doc comments correctly describe the eyes-closed/open alternation. No issues.

**`nfb_calibration_fail_reason.dart`** — Clean enhanced enum. File-level comment documents the C type mapping. NFB prefix present with rationale in the comment. No issues.

**`individual_nfb_data.dart`** — `@immutable` class, `const` constructor, all fields with correct defaults. `fromMap` uses `(v as num).toDouble()` pattern matching `sentinel.dart` convention. Timestamp sentinel handling is correct: `tsRaw == null || (tsRaw as int) < 0` guards the null branch, else branch uses promoted `tsRaw` for `DateTime.fromMillisecondsSinceEpoch`. `toMap` round-trips cleanly — timestamp encodes as `millisecondsSinceEpoch ?? -1`, failReason as `.code`, doubles pass through. Does not import `sentinel.dart` (correct — no sentinel float fields). No issues.

**`calibration_event.dart`** — Sealed class with two `final` subtypes. `deserialize` dispatches on `map['type']` with clear switch/case. Subtypes carry the right payloads: `CalibrationStage` for stage events, `IndividualNfbData` for completion. Doc comment shows exhaustive pattern matching example. No issues.

**`neiry_kit.dart`** — Four new exports added after existing model exports. All paths correct. No issues.

### Consistency Checks

- **`fromMap` key convention** — all models in the codebase use camelCase keys matching the C struct field names. `IndividualNfbData` follows this convention. ✅
- **`fromMap` parameter type** — `Map<Object?, Object?>` matches `NfbUserState.fromMap`, `ProductivityMetrics.fromMap`, etc. ✅
- **`toMap` return type** — `Map<String, dynamic>` is the standard MethodChannel argument type. ✅
- **Enum `fromCode` pattern** — identical structure to `NeiryErrorCode.fromCode`: linear scan, `ArgumentError` on unknown. ✅
- **Sealed class subtypes are `final`** — prevents further extension outside the library. ✅

### Critical Issues

None.

### Suggestions

**1. Spec note inconsistency on wire format stage values (informational, not blocking)**

The spec note `05-nfb-calibration.md` line 88 says `'stage': 1..4` in the wire format, but the Dart model uses 0-indexed codes (0–3) matching the C SDK enum. The native bridge (not yet written) must pass through the raw C enum values (0–3), not human-readable stage numbers (1–4). This is already the correct interpretation per the plan review, but the spec note should be updated to avoid confusion when implementing the native bridge.

REVIEW_PASS
