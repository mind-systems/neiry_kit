## Plan Review: Calibration Models (Round 2)

**Plan:** `.ai-factory/plans/05-calibration-models.md`
**Files Reviewed:** 5 tasks targeting 4 new files + 1 barrel update in `lib/src/models/`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — WARN: `individual_nfb_data.dart` is listed in the folder structure; new files (`calibration_stage.dart`, `nfb_calibration_fail_reason.dart`, `calibration_event.dart`) are not shown, but the structure is illustrative. No boundary or dependency violations.
- **RULES.md** — file does not exist. WARN (no conventions to check against).
- **ROADMAP.md** — OK. Plan aligns with the "calibration models" milestone. Enum name `NfbCalibrationFailReason` now matches both the plan and spec notes. The naming inconsistency flagged in round 1 (roadmap says `CalibrationFailReason`) is a roadmap-side nit, not a plan defect.

### Round 1 Fixes Verified

All 7 critical issues from the first review have been resolved:

| # | Issue | Status |
|---|---|---|
| 1 | CalibrationStage codes off by one (1-indexed → 0-indexed) | Fixed — `stage1(0), stage2(1), stage3(2), stage4(3)`, explicitly notes "0-indexed to match `clCIndividualNFBCalibrationStage` where `Stage_1 = 0`" |
| 2 | Missing `timestampMilli` field | Fixed — `timestamp: DateTime?`, nullable, with `-1` sentinel handling in `fromMap` and round-trip in `toMap` |
| 3 | Missing `individualPeakFrequency` field | Fixed — `double`, default `10.0`, listed as legacy alias |
| 4 | Wrong enum name (`CalibrationFailReason` → `NfbCalibrationFailReason`) | Fixed — file, class, and all references use `NfbCalibrationFailReason` |
| 5 | Wrong EventChannel reference (`calibrationProgress` → `nfbCalibration`) | Fixed — correctly references `NeiryEvents.nfbCalibration` |
| 6 | Missing `isValid` convenience getter | Fixed — `bool get isValid => failReason == NfbCalibrationFailReason.none;` included |
| 7 | Ambiguous factory function name | Fixed — pinned as `CalibrationEvent.deserialize(Map<Object?, Object?> map)` with rationale |

### Verification Against C SDK Header

Rechecked `official/iOS/CapsuleClient.framework/Headers/CNFBCalibrator.h`:

**`CalibrationStage` codes:** `stage1(0)` through `stage4(3)` — matches `clCIndividualNFBCalibrationStage_1 = 0` through `_4 = 3`. ✅

**`NfbCalibrationFailReason` codes:** `none(0)`, `tooManyArtifacts(1)`, `peakFrequencyAtBorder(2)` — matches `clC_IndividualNFBCalibrationFailReason_None = 0`, `_TooManyArtifacts = 1`, `_PeakIsABorder = 2`. ✅

**`IndividualNfbData` fields vs `clCIndividualNFBData`:**

| C struct field | Plan field | Default | Match |
|---|---|---|---|
| `int64_t timestampMilli = -1` | `DateTime? timestamp` (null when -1) | — | ✅ |
| `clCIndividualNFBCalibrationFailReason failReason` | `NfbCalibrationFailReason failReason` | `.none` | ✅ |
| `float individualFrequency = 10.F` | `double individualFrequency` | `10.0` | ✅ |
| `float individualPeakFrequency = 10.F` | `double individualPeakFrequency` | `10.0` | ✅ |
| `float individualPeakFrequencyPower = 10.F` | `double individualPeakFrequencyPower` | `10.0` | ✅ |
| `float individualPeakFrequencySuppression = 2.F` | `double individualPeakFrequencySuppression` | `2.0` | ✅ |
| `float individualBandwidth = 6.F` | `double individualBandwidth` | `6.0` | ✅ |
| `float individualNormalizedPower = 0.5F` | `double individualNormalizedPower` | `0.5` | ✅ |
| `float lowerFrequency = 7.F` | `double lowerFrequency` | `7.0` | ✅ |
| `float upperFrequency = 13.F` | `double upperFrequency` | `13.0` | ✅ |

All 10 fields present with correct types and defaults. No missing or extra fields. ✅

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- All 7 issues from round 1 addressed cleanly — no partial fixes or regressions.
- Every field in `clCIndividualNFBData` is now accounted for with correct defaults and nullability.
- The `deserialize` name choice for the sealed class dispatch is well-motivated and avoids confusion with `fromMap` on data models.
- The `(map['key'] as num).toDouble()` pattern correctly handles `StandardMessageCodec` int/double ambiguity, consistent with `sentinel.dart`.
- The `toMap` → `fromMap` round-trip is symmetric: timestamp encodes as `-1` when null, `failReason` encodes as `.code`, all doubles pass through directly.
- Phase ordering (enums → model → sealed class → barrel) respects compile-time dependencies.
- The "Do NOT import sentinel.dart" note prevents a misleading import in the only model that has no sentinel float fields.

PLAN_REVIEW_PASS
