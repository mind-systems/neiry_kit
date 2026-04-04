## Code Review Summary

**Plan Reviewed:** `06-export-unit-tests.md`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — PASS. Plan respects every relevant rule: barrel is the public API (principle 4), sentinel mapped to null at Dart boundary (principle 5), internal `sentinel.dart` stays unexported, models are immutable value types (principle 2). No boundary violations.
- **RULES.md** — WARN (file does not exist). No project-level rules to check against.
- **ROADMAP.md** — PASS. Plan implements the "export + unit tests" milestone under "Dart models" exactly as scoped. No extra scope drift.
- **Skill context** — WARN (`aif-review/SKILL.md` does not exist). No project-specific review rules to apply.

### Critical Issues

None.

### Detailed Verification

**Phase 1 — Barrel export (Task 1)**

Verified the barrel file (`lib/neiry_kit.dart`) currently has 8 exports. The plan correctly identifies exactly 8 model files that exist on disk but are missing from the barrel:

| Plan path | File exists | Currently exported |
|---|---|---|
| `src/models/device_info.dart` | ✅ | ❌ → add |
| `src/models/neiry_error.dart` | ✅ | ❌ → add |
| `src/models/nfb_user_state.dart` | ✅ | ❌ → add |
| `src/models/physio_states.dart` | ✅ | ❌ → add |
| `src/models/emotions_states.dart` | ✅ | ❌ → add |
| `src/models/productivity_metrics.dart` | ✅ | ❌ → add |
| `src/models/productivity_indexes.dart` | ✅ | ❌ → add |
| `src/models/productivity_baselines.dart` | ✅ | ❌ → add |

Correctly excludes `internal/sentinel.dart` per architecture principle 4 and the "internal-only" comment in the file itself.

**Phase 2 — Enum tests (Task 2)**

- `NeiryErrorCode`: plan says 17 values — counted 17 in `neiry_error_code.dart` (ok=0 through unknown=255). ✅
- `CalibrationStage`: plan says 4 values (0–3) — matches `calibration_stage.dart`. ✅
- `NfbCalibrationFailReason`: plan says 3 values (0–2) — matches `nfb_calibration_fail_reason.dart`. ✅
- Round-trip and `fromCode` throw-on-unknown patterns match the actual `fromCode` implementations (all use linear scan + `ArgumentError`). ✅
- These three enums were not covered in `channel_names_test.dart` (which only tests `NeiryDeviceType`, `NeiryDeviceMode`, `NeiryConnectionState`). No duplication. ✅

**Phase 2 — Sentinel / fromMap tests (Task 3)**

Each model's test spec verified against actual `fromMap` implementation:

- `NfbUserState`: 5 nullable doubles via `orNull` + `ts` as int → `DateTime`. Plan tests both `-1.0` (double) and `-1` (int) — `orNull` handles both via `(v as num).toDouble()`. ✅
- `PhysiologicalStatesValue`: 6 nullable doubles + 2 required bools (`nfbArtifacts`, `cardioArtifacts`) + `ts`. Plan field list matches code exactly. ✅
- `EmotionsStates`: 5 nullable doubles + `ts`. ✅
- `ProductivityBaselines`: 6 nullable doubles + `ts`. ✅
- `ProductivityIndexes`: 6 nullable doubles + `relaxation` (int), `stress` (int), `hasArtifacts` (bool) + `ts`. ✅
- `DeviceInfo`: `serial` (String), `name` (String), `type` (int → `NeiryDeviceType`). No sentinel fields. ✅
- `NeiryError`: `message` (String), `success` (bool), `code` (int → `NeiryErrorCode`). No sentinel fields. ✅

**Phase 2 — Uint8List, CalibrationEvent, round-trip (Task 4)**

- `ProductivityMetrics`: plan says 10 nullable doubles — matches code (fatigueScore through accumulatedFatigue). Plan correctly identifies 3 `artifactsData` sub-cases: null → null, empty `Uint8List(0)` → non-null with length 0, populated → preserved. All match the actual `fromMap` null-check logic. ✅
- `CalibrationEvent.deserialize`: plan's dispatch test `{'type': 'stage', 'stage': 2}` → `CalibrationStageFinished(stage: CalibrationStage.stage3)` is correct (`fromCode(2)` → `stage3`). The `'done'` and unknown-type cases match the `switch` in `calibration_event.dart`. ✅
- `IndividualNfbData` round-trip: plan correctly identifies 8 double fields + `failReason` (int→enum) + `ts` (nullable). The `toMap` → `fromMap` → `toMap` cycle tests the `-1` sentinel encoding for null timestamps, which matches `timestamp?.millisecondsSinceEpoch ?? -1`. ✅

**Test style**

Plan follows the established style from `channel_names_test.dart`: grouped tests, comment section dividers, `flutter_test` + barrel import. New file `test/models_test.dart` keeps channel tests separate from model tests. ✅

### Suggestions

None.

### Positive Notes

- Thorough coverage: every model, every sentinel field, every enum — nothing is skipped.
- The int-vs-double sentinel test (Task 3, `NfbUserState`) directly addresses a real `StandardMessageCodec` edge case that the `orNull` helper was specifically designed for.
- CalibrationEvent dispatch test covers the sealed-class pattern exhaustively (both valid subtypes + unknown type error).
- The `IndividualNfbData` round-trip with null timestamp validates the sentinel encoding contract that the native bridges will depend on.

PLAN_REVIEW_PASS
