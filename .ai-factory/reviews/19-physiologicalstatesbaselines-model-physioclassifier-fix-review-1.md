## Code Review: PhysiologicalStatesBaselines model + PhysioClassifier fix

**Plan:** `19-physiologicalstatesbaselines-model-physioclassifier-fix.md`
**Risk Level:** Low

### Verification

- `flutter test test/models_test.dart` — 73/73 pass
- `flutter analyze` — no issues

### Files Reviewed

| File | Status |
|---|---|
| `lib/src/models/physio_baselines.dart` | New — model |
| `lib/src/api/classifiers/physio_classifier.dart` | Modified — stream type + method signature |
| `lib/neiry_kit.dart` | Modified — barrel export |
| `test/models_test.dart` | Modified — 3 new tests |

### Critical Issues

None.

### Minor Issues

1. **Stale doc comment in `startBaselineCalibration`** (`physio_classifier.dart:162`)
   Line 162 still says "receive the completed baselines **blob** via [calibrated]". The word "blob" is leftover from the old `Uint8List` API — should say "baselines data" or "structured baselines" for consistency with the updated `calibrated` getter doc (line 140). Not a runtime issue, purely cosmetic.

### Analysis

**Model (`physio_baselines.dart`):**
- `@immutable`, `const` constructor, all nullable fields — matches architecture principle #2 (immutable value types). Correct departure from `ProductivityBaselines` where `timestamp` was non-nullable: here the C struct uses `-1` sentinel for `timestampMilli`, so `DateTime?` is the right choice.
- `fromMap` timestamp handling: null-safe, casts `tsRaw as int` only after null check, rejects negatives. Functionally equivalent to `IndividualNfbData.fromMap` (lines 60–66) which uses a slightly different branch structure but same logic.
- `orNull` from `internal/sentinel.dart` used for all double fields — consistent with every other model in the codebase.
- `toMap` reverse-sentinel: null → `-1.0` for doubles, null → `-1` for timestamp. Types are correct for `StandardMessageCodec` encoding (int and double are both supported).
- Edge cases verified: `ts: 0` → valid epoch DateTime, `alpha: 0.0` → `orNull` returns `0.0` (non-negative), all-null constructor → all sentinels emitted.

**PhysioClassifier changes:**
- `_calibrated` decoder changed from `(map) => map['baselines'] as Uint8List` to `PhysiologicalStatesBaselines.fromMap`. This is a contract change: the bridge must now emit baselines fields as top-level map keys (not nested under a `baselines` key). This matches the wire format specified in `10-explore-physio-emotions.md` (lines 160–169). Correct.
- `importBaselines(PhysiologicalStatesBaselines baselines)` passes `baselines.toMap()` as the `NeiryArgs.baselines` argument. The bridge will receive a `Map<String, dynamic>` with 6 keys and sentinel values for nulls — exactly what `clCPhysiologicalStates_ImportBaselines` needs after deserialization to the C struct. Correct.
- No remaining `Uint8List` usage in the file — `package:flutter/services.dart` import is still needed for `MethodChannel`/`EventChannel`. Clean.
- Doc comments on `calibrated` getter and `importBaselines` updated appropriately.

**Barrel export (`neiry_kit.dart`):**
- `physio_baselines.dart` inserted between `nfb_user_state.dart` (line 23) and `physio_states.dart` (line 25) — alphabetically correct (`physio_b` < `physio_s`).

**Tests (`models_test.dart`):**
- 3 tests cover: all-sentinel → all-null, valid round-trip (`fromMap` → `toMap` → verify), mixed sentinel/valid with `toMap` re-emit check.
- Test group placed after `PhysiologicalStatesValue` and before `EmotionsStates` — logical ordering.
- Tests use the barrel import, not internal paths — correct per architecture rules.

### Positive Notes

- Implementation is minimal and focused — exactly the changes needed, nothing extra.
- Model pattern is consistent with the 7 existing models in the codebase.
- The `fromMap`/`toMap` round-trip is fully invertible: `fromMap(toMap(fromMap(x))) == fromMap(x)` for all valid inputs.

REVIEW_PASS
