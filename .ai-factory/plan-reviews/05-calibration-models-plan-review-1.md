## Plan Review: Calibration Models

**Plan:** `.ai-factory/plans/05-calibration-models.md`
**Files Reviewed:** 5 tasks targeting 4 new files + 1 barrel update in `lib/src/models/`
**Risk Level:** 🔴 High

### Context Gates

- **ARCHITECTURE.md** — WARN: `individual_nfb_data.dart` is already listed in the folder structure example; new files (`calibration_stage.dart`, `calibration_event.dart`, fail reason file) are not shown, but the structure is illustrative, not exhaustive.
- **RULES.md** — file does not exist. WARN (no conventions to check against).
- **ROADMAP.md** — WARN: Roadmap milestone description says `CalibrationFailReason`, but spec notes (`02-dart-models.md`, `05-nfb-calibration.md`) consistently use `NfbCalibrationFailReason`. Minor roadmap naming inconsistency that propagated into the plan.

### Verification Against C SDK Header

Checked `official/iOS/CapsuleClient.framework/Headers/CNFBCalibrator.h` line by line.

**`clCIndividualNFBCalibrationStage` enum:**

```c
typedef enum clCIndividualNFBCalibrationStage {
    clCIndividualNFBCalibrationStage_1 = 0,  // not 1
    clCIndividualNFBCalibrationStage_2,       // 1
    clCIndividualNFBCalibrationStage_3,       // 2
    clCIndividualNFBCalibrationStage_4,       // 3
} clCIndividualNFBCalibrationStage;
```

**`clCIndividualNFBCalibrationFailReason` enum:**

```c
typedef enum clCIndividualNFBCalibrationFailReason {
    clC_IndividualNFBCalibrationFailReason_None = 0,
    clC_IndividualNFBCalibrationFailReason_TooManyArtifacts,  // 1
    clC_IndividualNFBCalibrationFailReason_PeakIsABorder,     // 2
} clCIndividualNFBCalibrationFailReason;
```

Fail reason values (0, 1, 2) match the plan. ✅

**`clCIndividualNFBData` struct:**

```c
typedef struct clCIndividualNFBData {
    int64_t timestampMilli = -1;
    clCIndividualNFBCalibrationFailReason failReason = ...None;
    float individualFrequency = 10.F;
    float individualPeakFrequency = 10.F;       // ← missing from plan
    float individualPeakFrequencyPower = 10.F;
    float individualPeakFrequencySuppression = 2.F;
    float individualBandwidth = 6.F;
    float individualNormalizedPower = 0.5F;
    float lowerFrequency = 7.F;
    float upperFrequency = 13.F;
} clCIndividualNFBData;
```

### Critical Issues

**1. CalibrationStage integer codes are off by one — runtime crash on every stage event**

Task 1 defines `stage1(1), stage2(2), stage3(3), stage4(4)`. The C SDK uses 0-indexed values: `Stage_1 = 0, Stage_2 = 1, Stage_3 = 2, Stage_4 = 3`. When the native bridge sends `{'type': 'stage', 'stage': 0}` for the first stage, `CalibrationStage.fromCode(0)` will find no match and throw `ArgumentError`. Every calibration attempt will crash on the first stage callback.

Fix: change to `stage1(0), stage2(1), stage3(2), stage4(3)`.

**2. Missing `timestampMilli` field in `IndividualNfbData`**

The C struct has `int64_t timestampMilli = -1`. The plan omits it entirely. The 05-nfb-calibration spec explicitly includes `final DateTime timestamp` and notes "only timestamp can be -1". This is a sentinel field — it should be `DateTime?` (null when -1), decoded via:

```dart
timestamp: map['ts'] == null || (map['ts'] as int) < 0
    ? null
    : DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
```

This matters for `toMap()` round-trip: when `importCalibrationData()` sends data to native, the bridge will construct a `clCIndividualNFBData` struct. A missing timestamp means the native side either gets a wrong value or has to fill in -1 — the Dart model should own this explicitly.

**3. Missing `individualPeakFrequency` field in `IndividualNfbData`**

The C struct has `float individualPeakFrequency = 10.F` (described as "Individual NFB peak frequency" — legacy alias for `individualFrequency`). The 05-nfb-calibration spec includes it. The plan omits it.

This breaks the `toMap()` → `importCalibrationData()` round-trip: calibration produces a value for this field, `fromMap` ignores it, then `toMap` doesn't include it — the re-imported struct will use the default (10.0) instead of the actual calibrated value. This silently corrupts calibration data.

Fix: add `final double individualPeakFrequency` (default `10.0`, non-nullable) to the model, `fromMap`, and `toMap`.

**4. Enum naming: `CalibrationFailReason` should be `NfbCalibrationFailReason`**

Both spec notes (`02-dart-models.md` line 61, `05-nfb-calibration.md` line 79) consistently use `NfbCalibrationFailReason`. The C type is `clCIndividualNFBCalibrationFailReason`. The NFB qualifier is important because this enum is specific to NFB calibration — physio and productivity have their own separate calibration mechanisms with different failure modes. Using the generic name `CalibrationFailReason` creates ambiguity.

Fix: rename to `NfbCalibrationFailReason`, file to `nfb_calibration_fail_reason.dart`, update all references in Tasks 3–5.

**5. Wrong EventChannel reference in Task 4**

Task 4 says the factory "will be called by the Dart API layer when listening to `NeiryEvents.calibrationProgress`". This identifier doesn't exist in `channel_names.dart`. The correct EventChannel is `NeiryEvents.nfbCalibration` (line 43 of `channel_names.dart`).

**6. Missing `isValid` convenience getter on `IndividualNfbData`**

The 05-nfb-calibration spec (line 51) defines `bool get isValid => failReason == NfbCalibrationFailReason.none;`. This should be included — the example app and `mind_mobile` will need to check calibration validity before starting classifiers, and this getter encapsulates that check instead of leaking the `none` check to every call site.

**7. Ambiguous factory function in Task 4**

Task 4 says "Add a top-level factory function (or static method on CalibrationEvent)". The plan should commit to one choice. A static method `CalibrationEvent.fromMap(Map<Object?, Object?> map)` is more discoverable and consistent with how other models expose deserialization (even though the spec says "CalibrationEvent itself has no fromMap" — a dispatch method with a different name like `CalibrationEvent.deserialize()` works too). Pin the name so the implementer and the API layer agree on the call site.

### Positive Notes

- The sealed class design with exhaustive `switch` is the right pattern for a polymorphic event stream — type-safe and extensible.
- The `fromMap` / `toMap` choice for `IndividualNfbData` correctly follows the architecture's "no raw maps cross the API boundary" rule while providing the serialization needed for `importCalibrationData()`.
- Task phases are correctly ordered with dependency chains (enums → model → sealed class → barrel).
- The `(map['key'] as num).toDouble()` pattern in Task 3 correctly handles Flutter's `StandardMessageCodec` int/double ambiguity, matching the sentinel helper's approach.
- Single commit plan keeps the changeset atomic and reviewable.
