## Code Review: Scalar + Signal Models

**Plan:** `.ai-factory/plans/03-scalar-signal-models.md`
**Files reviewed:** 5 new model files, cross-referenced against C SDK headers, existing codebase, ARCHITECTURE.md, and spec notes

### Files Reviewed

| File | Verdict |
|---|---|
| `lib/src/models/device_info.dart` | OK |
| `lib/src/models/neiry_error.dart` | OK |
| `lib/src/models/nfb_user_state.dart` | OK |
| `lib/src/models/physio_states.dart` | OK |
| `lib/src/models/emotions_states.dart` | OK |

### C Header Verification

Every field in every model was verified against the canonical C headers:

- **`clCError`** (`CError.h:28-32`): `message[256]` → `String`, `success` → `bool`, `code` → `NeiryErrorCode` via `fromCode(int)`. All three fields present and correctly typed.
- **`clCDeviceInfo`** (`CDeviceInfo.h`): Opaque handle with accessor functions `GetSerial` → `String`, `GetName` → `String`, `GetType` → `NeiryDeviceType` via `fromCode(int)`. All three fields present.
- **`clCNFB_UserState`** (`CNFB.h:24-31`): `timestampMilli` → `DateTime`, 5 float fields (`delta`, `theta`, `alpha`, `smr`, `beta`) all default `-1.F` → `double?` via `orNull`. Complete match.
- **`clCPhysiologicalStates_Value`** (`CPhysiologicalStates.h:14-24`): `timestampMilli` → `DateTime`, 6 float fields (`relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress`) all default `-1.F` → `double?` via `orNull`, 2 bool fields (`nfbArtifacts`, `cardioArtifacts`) default `false` → `bool` required. Complete match.
- **`clCEmotions_States`** (`CEmotions.h:14-21`): `timestampMilli` → `DateTime`, 5 float fields (`attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl`) all default `-1.F` → `double?` via `orNull`. Complete match.

### Convention Compliance

- **`@immutable` + `const` constructor + `fromMap` factory**: All 5 models follow this pattern, matching ARCHITECTURE.md §Key Principles #2 and the existing `NeiryErrorCode`/`NeiryException` style.
- **`Map<Object?, Object?>` parameter type**: Correct for Flutter's `StandardMessageCodec`, consistent across all models.
- **Sentinel handling**: Signal models import the shared `orNull` from `internal/sentinel.dart` (handles both `int` and `double` via `num.toDouble()`) rather than inlining a local helper. This is more robust than the simplified example in ARCHITECTURE.md which casts directly to `double`.
- **Import paths**: `../channel/enums.dart` (DeviceInfo), `neiry_error_code.dart` (NeiryError), `internal/sentinel.dart` (signal models) — all resolve to existing files.
- **Barrel export**: Not modified — correctly deferred to the "export + unit tests" milestone per ROADMAP.md.
- **Dependency rules**: Models import only from `channel/` (enums) and `internal/` (sentinel), never from `api/` or platform code. Compliant with ARCHITECTURE.md dependency diagram.

### Critical Issues

None.

### Non-Critical Observations

None requiring action. The code is minimal and correct.

REVIEW_PASS
