## Plan Review: Scalar + Signal Models

**Plan file:** `.ai-factory/plans/03-scalar-signal-models.md`
**Files reviewed:** 5 tasks, cross-referenced against C SDK headers, existing codebase, ARCHITECTURE.md, ROADMAP.md, and spec notes

**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — all models go into `lib/src/models/`, use `@immutable` + `fromMap` factories, sentinel-to-null via imported `orNull`. Dependency rules respected (models import from `channel/` for enums, `internal/` for sentinel helper, nothing else).
- **RULES.md:** WARN — file does not exist. No blocking conventions to check.
- **ROADMAP.md:** PASS — plan maps exactly to the "scalar + signal models" milestone. Barrel export and unit tests are correctly deferred to their own milestone.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- **All field mappings verified against C headers.** Every field in every task was cross-checked against the actual SDK headers (`CError.h`, `CDeviceInfo.h`, `CNFB.h`, `CPhysiologicalStates.h`, `CEmotions.h`). All match exactly — including the `success` bool on `clCError` and the `nfbArtifacts`/`cardioArtifacts` booleans on `clCPhysiologicalStates_Value` that aren't mentioned in the spec summary.
- **Correct sentinel handling.** Signal models import the shared `orNull` from `internal/sentinel.dart` (which safely handles both `int` and `double` via `num.toDouble()`) rather than inlining a local helper. This is more robust than the simplified example in ARCHITECTURE.md.
- **Import paths are all correct.** `../channel/enums.dart` for `NeiryDeviceType`, `neiry_error_code.dart` for `NeiryErrorCode`, `internal/sentinel.dart` for `orNull` — all resolve to existing files.
- **`fromMap` signature uses `Map<Object?, Object?>`** — correct for Flutter's `StandardMessageCodec`, consistent with the ARCHITECTURE.md convention.
- **Clean scope.** Five models, two commits, no scope creep. Barrel export and tests deferred to the correct milestone per ROADMAP.
- **`neiry_error.dart` naming** is more consistent with the existing convention (`neiry_error_code.dart`, `neiry_exception.dart`) than the spec's abbreviated `error.dart`.

PLAN_REVIEW_PASS
