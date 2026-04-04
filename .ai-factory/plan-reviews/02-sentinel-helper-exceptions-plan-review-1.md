# Plan Review: Sentinel helper + exceptions

**Plan file:** `.ai-factory/plans/02-sentinel-helper-exceptions.md`
**Files Reviewed:** plan (4 tasks) + codebase context (barrel, enums, channel_names, ARCHITECTURE, spec notes, C SDK header)
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** ✅ WARN — Plan aligns with architecture (models layer, barrel exports, sentinel principle 5). One inconsistency: the code example in ARCHITECTURE.md for `orNull` has a type-safety bug that the plan inherits (see Critical Issues).
- **RULES.md:** not present (WARN — no file).
- **ROADMAP.md:** ✅ Plan covers the full "sentinel helper + exceptions" milestone scope. Minor note: roadmap says "16 values" for `NeiryErrorCode` but the C SDK header has 17 (0–15 + 255); the plan correctly lists 17.

## Critical Issues

### 1. `orNull` implementation won't compile and has a runtime edge case

**File:** `lib/src/models/internal/sentinel.dart` (Task 1)

The plan describes the implementation as:

```dart
double? orNull(Object? v) => v == null || (v as double) < 0 ? null : v;
```

This has two problems:

**a) Compile error — return type mismatch.**
After `(v as double) < 0`, the variable `v` is still typed `Object?` — Dart's `as` cast does not promote the variable (only `is` checks do). Returning `v` where the return type is `double?` is a compile error in Dart 3.x with sound null safety. The implementation must assign the cast result to a typed local variable.

**b) Runtime `TypeError` when platform channel delivers `int`.**
Flutter's `StandardMessageCodec` maps native integers to Dart `int`, not `double`. If the native bridge sends sentinel `-1` as an integer (rather than `-1.0` as a float), `v as double` throws a `TypeError` at runtime. Using `v as num` with `.toDouble()` is the defensive pattern for platform channel interop.

**Fix — replace the described implementation with:**

```dart
double? orNull(Object? v) {
  if (v == null) return null;
  final d = (v as num).toDouble();
  return d < 0 ? null : d;
}
```

This resolves both issues: `num` accepts both `int` and `double` from the platform channel, `.toDouble()` normalizes the type, and `d` is properly typed as `double` for the return.

> Note: the ARCHITECTURE.md code example contains the same bug — the plan shouldn't copy it verbatim. The shared helper is the canonical place to get this right since every model's `fromMap` factory will depend on it.

## Suggestions

No additional suggestions — the plan is otherwise clean, well-scoped, and correctly structured.

## Positive Notes

- **Enum values verified against C SDK header.** All 17 `clCError_Code` values (0–15 + 255) match exactly. The plan corrects the roadmap's "16 values" count.
- **Follows existing codebase patterns.** The `NeiryErrorCode` enum uses the same `final int code` + `fromCode` factory pattern as the enums in `channel/enums.dart`. Consistent and discoverable.
- **Correct barrel export decisions.** `sentinel.dart` is internal-only (not exported), while `neiry_error_code.dart` and `neiry_exception.dart` are public. This matches architecture principle 4 exactly.
- **Clean exception hierarchy.** Three concrete subclasses with hardcoded error codes and overridable messages — minimal API surface, easy to extend later when more bridge error scenarios are identified.
- **Appropriate scoping.** The plan correctly omits the `PlatformException` → `NeiryException` conversion logic (that belongs in the Dart API layer, a future milestone) and omits tests (covered by the separate "export + unit tests" milestone).
- **File placement is correct.** `models/internal/` for the shared codec helper, `models/` for the public enum and exception — matches the architecture's folder structure.
