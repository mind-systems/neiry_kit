## Code Review Summary

**Plan Reviewed:** `.ai-factory/plans/44-memsdata-model.md`
**Files Affected:** 2 (new model + barrel edit)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** PASS — model goes in `lib/src/models/`, uses `@immutable` + `const` constructor + `fromMap` factory, barrel export via `lib/neiry_kit.dart`. All dependency rules respected.
- **RULES.md:** WARN — file does not exist. No project-level rules to check.
- **ROADMAP.md:** PASS — plan matches the first sub-milestone under "MEMS classifier" exactly. Scope is correctly bounded to the model + export only.

### Critical Issues

None.

### Issues

**Task 2 — wrong alphabetical insertion point.** The plan says to insert `mems_data.dart` "between `eeg_data.dart` and `emotions_states.dart` lines". This is incorrect. The barrel file's model exports are alphabetical:

```
export 'src/models/eeg_data.dart';             // e
export 'src/models/emotions_states.dart';      // e
export 'src/models/individual_nfb_data.dart';  // i
                                                // ← mems_data.dart goes here (m)
export 'src/models/neiry_error.dart';          // n
```

`m` comes after `i` and before `n`. The correct insertion point is after `individual_nfb_data.dart` (line 18) and before `neiry_error.dart` (line 19). Fix the plan text to avoid a misordered barrel file.

### Observations (non-blocking)

**Record type is a new pattern.** The plan uses Dart record types `({double x, double y, double z})` for `accelerometer` and `gyroscope`. No existing model in the codebase uses records — all use flat scalar fields. This is a reasonable choice for 3D coordinate data (groups related values, avoids 6 loose fields), and the SDK constraint (`^3.11.0`) fully supports it. Worth being aware of as a conscious divergence, but not a problem.

### Positive Notes

- Scope is minimal and well-bounded — exactly one model file and one barrel edit. No over-engineering.
- Correctly identifies that MEMS data has no sentinel values, avoiding unnecessary `orNull` usage.
- Correctly identifies that `NeiryEvents.memsData` already exists in `channel_names.dart` and explicitly warns against duplicating it.
- `fromMap` signature uses `Map<Object?, Object?>` consistent with all existing models (Flutter's `StandardMessageCodec` returns this type, not `Map<String, dynamic>`).
- Map keys (`ax`/`ay`/`az`/`gx`/`gy`/`gz`/`ts`) are compact and consistent with the bridge serialization pattern used for other models.

PLAN_REVIEW_PASS
