# Plan Review: CardioClassifier (Round 2)

**Plan:** `.ai-factory/plans/13-cardioclassifier.md`
**Files Reviewed:** 4 tasks across 4 files
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan aligns with the layered plugin architecture (models → channel → api → barrel). Dependency rules respected. No boundary violations.
- **RULES.md:** File not present. `WARN` — no explicit convention violations detected; plan follows established codebase patterns.
- **ROADMAP.md:** `WARN` — Roadmap entry for CardioClassifier still lists `errorStream` which the plan correctly drops (C API has no error callback). Roadmap should be updated to match the plan after implementation.

## Review of Round 1 Fixes

All three critical issues from plan-review-1 have been resolved:

1. **`errorStream` removed** — Plan now explicitly states "No `errorStream`" with correct reasoning (C API `CCardio.h` has no `SetOnErrorEvent`). No `cardioError` channel constant is added. ✓
2. **`calibratedStream` added** — Plan now wires `Stream<void>` to the existing `NeiryEvents.cardioCalibratedEvent` EventChannel, using `.map((_) {})` directly instead of the `_eventStream` helper (correct, since the callback carries no data payload). ✓
3. **Float fields made non-nullable** — Plan now uses required `double` (not `double?` via `orNull`) for `heartRate`, `stressIndex`, `kaplanIndex`, with doc comments stating values are only meaningful when `metricsAvailable` is `true`. This matches the C struct's `0.F` initialization and avoids the misleading `orNull` pattern. ✓

## Critical Issues

None.

## Suggestions

None.

## Positive Notes

- The plan is precise and complete. Every task references the correct channel constants (`NeiryChannels.cardio`, `NeiryEvents.cardioData`, `NeiryEvents.ppgData`, `NeiryEvents.cardioCalibratedEvent`) — all verified present in `channel_names.dart`.
- Import paths in Task 3 are all verified correct relative to `lib/src/api/classifiers/`.
- The `calibratedStream` design correctly avoids the `_eventStream<T>` helper (which casts to `Map<Object?, Object?>`) since the native event carries no typed payload — clean handling of the void-callback case.
- `PpgData` model follows the batched-data pattern from `EegData` (list fields, no sentinel conversion), which is the right choice for raw signal data.
- Barrel export placement in Task 4 is alphabetically correct: `cardio_classifier` before `emotions_classifier`; `cardio_data` between `calibration_stage` and `device_info`; `ppg_data` between `physio_states` and `productivity_baselines`.
- The two-factory pattern (`CardioClassifier` / `CardioClassifier.withCalibration`) exactly mirrors `ProductivityClassifier` — same guards, same `_nativeReady` / `_createError` / `_disposed` state, same idempotent `dispose()`.

PLAN_REVIEW_PASS
