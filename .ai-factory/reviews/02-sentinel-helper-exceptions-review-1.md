# Code Review: Sentinel helper + exceptions

**Plan file:** `.ai-factory/plans/02-sentinel-helper-exceptions.md`
**Files reviewed:** 4 new/modified files (`sentinel.dart`, `neiry_error_code.dart`, `neiry_exception.dart`, `neiry_kit.dart`)
**Verification:** `flutter analyze` — no issues found

## Files Reviewed

### `lib/src/models/internal/sentinel.dart` (new)

- `orNull(Object? v)` correctly casts to `num` (not `double`) to handle both `int` and `double` from `StandardMessageCodec`. This addresses the plan review's critical issue.
- Typed local `final d` ensures `double?` return type compiles under sound null safety.
- Sentinel contract is correct: any negative value → `null`, `null` → `null`, zero-or-positive → returned as `double`.
- Not exported from barrel — correct, matches architecture principle 4.

### `lib/src/models/neiry_error_code.dart` (new)

- All 17 values verified against `CError.h` (`clCError_Code`): 0–15 auto-incremented + 255. Exact match.
- Pattern (`final int code`, `const` constructor, `fromCode` with `ArgumentError`) matches `enums.dart` precisely.
- `fromCode` linear scan is appropriate — 17 values, called infrequently during error handling.

### `lib/src/models/neiry_exception.dart` (new)

- `NeiryException implements Exception` with `const` constructor — correct base.
- `toString()` produces `'NeiryException(NeiryErrorCode.failedToConnect): message'` — readable for debugging.
- Three subclasses use valid Dart 3.x super parameter syntax: `super.message` forwarded alongside `: super(code: ...)` in the initializer list. No conflict — `message` goes via super parameter, `code` goes via initializer list. Verified by `flutter analyze`.
- Each subclass allows optional `message` override via the named parameter.
- Error code assignments are semantically correct:
  - `BluetoothDisabledException` → `failedToConnect` (maps to BLE adapter issues) ✅
  - `DeviceNotConnectedException` → `deviceError` (maps to device-level failure) ✅
  - `CalibrationRequiredException` → `individualNfbNotCalibrated` (direct match) ✅

### `lib/neiry_kit.dart` (modified)

- Added exports for `neiry_error_code.dart` and `neiry_exception.dart`. Correctly omits `internal/sentinel.dart`.
- Export order: channel files first, then models — consistent grouping.

## Critical Issues

None.

## Suggestions

None.

## Positive Notes

- **Plan review feedback fully addressed.** The `orNull` implementation correctly uses `num` + `.toDouble()` with a typed local, fixing both the compile error and the runtime `TypeError` identified in plan-review-1.
- **Enum values are an exact 1:1 match with the C SDK header.** Verified all 17 values against `CError.h` including the explicit `= 255` for `clCError_Unknown`.
- **Consistent patterns.** `NeiryErrorCode` follows the exact same structure as the three enums in `enums.dart` — discoverable for anyone already familiar with the codebase.
- **Static analysis passes cleanly.** `flutter analyze` reports zero issues across the entire project.
- **Correct scoping.** Internal helper stays internal; public types are exported. No over-exposure of implementation details.

REVIEW_PASS
