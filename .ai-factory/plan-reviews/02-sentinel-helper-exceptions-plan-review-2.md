# Plan Review: Sentinel helper + exceptions (Round 2)

**Plan file:** `.ai-factory/plans/02-sentinel-helper-exceptions.md`
**Files Reviewed:** plan (4 tasks) + codebase context (barrel, enums, channel_names, ARCHITECTURE, spec notes, C SDK header `CError.h`, previous plan-review-1)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** ✅ PASS — Plan aligns with all architecture principles. File placement (`models/internal/` for codec helper, `models/` for public types), barrel export strategy (principle 4), and sentinel-to-null conversion (principle 5) are all correct. The `orNull` implementation now correctly avoids the type-safety bug present in the ARCHITECTURE.md code example.
- **RULES.md:** WARN — file does not exist.
- **ROADMAP.md:** ✅ PASS — Plan covers the full "sentinel helper + exceptions" milestone scope. The roadmap says "16 values" for `NeiryErrorCode` but the C SDK header has 17 (0–15 + 255); the plan correctly lists 17 — this is a minor roadmap text inconsistency, not a plan defect.

## Critical Issues

None.

## Suggestions

None.

## Positive Notes

- **Previous review's critical issue resolved.** The `orNull` implementation now uses `(v as num).toDouble()` with a typed local `d`, which fixes both the `TypeError` on platform-delivered `int` sentinels and the Dart 3.x compile error from returning an unpromoted `Object?`. The plan also includes clear inline rationale for both design decisions.
- **Enum values verified against C SDK header.** All 17 `clCError_Code` values from `CError.h` (0–15 auto-incremented + 255) match the plan's `NeiryErrorCode` enum exactly.
- **Follows existing codebase patterns.** `NeiryErrorCode` uses the same `final int code` + `fromCode(int)` + `ArgumentError` pattern as the three enums in `channel/enums.dart`.
- **Correct barrel export decisions.** `sentinel.dart` stays internal; `neiry_error_code.dart` and `neiry_exception.dart` are exported. Matches architecture principle 4.
- **Clean exception hierarchy.** Three concrete subclasses with hardcoded error codes and overridable messages — minimal surface, easy to extend when more bridge error scenarios are identified.
- **Appropriate scope boundaries.** The plan correctly omits `PlatformException` → `NeiryException` translation (belongs in the Dart API layer milestone) and omits tests (covered by the separate "export + unit tests" milestone in the roadmap).

PLAN_REVIEW_PASS
