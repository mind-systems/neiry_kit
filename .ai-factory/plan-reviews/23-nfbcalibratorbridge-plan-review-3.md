# Plan Review: NfbCalibratorBridge (iOS) — Review 3

**Plan file:** `.ai-factory/plans/23-nfbcalibratorbridge.md`
**Files Reviewed:** 7 plan tasks across 3 phases, verified against 10 codebase files
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md** — no violations. File placement (`ios/Classes/NfbCalibratorBridge.swift`, not inside `classifiers/`), dependency rules, bridge-per-module principle, `DeviceStreamHandler` reuse, and `allStreamHandlers()` pattern all align.
- **RULES.md** — not present (`WARN`, non-blocking).
- **ROADMAP.md** — `WARN`: the ROADMAP entry for `NfbCalibratorBridge` still says "do NOT emit on EventChannel for quick mode." The plan correctly diverges — the Dart API uses the EventChannel for both modes (`nfb_calibrator.dart:191–211`). The ROADMAP bullet is stale and should be updated after this plan lands to avoid confusing the Android bridge implementer. Not blocking.

## Review of fixes from Reviews 1 and 2

All four issues from prior reviews have been addressed:

1. **Quick-mode data delivery** (Review 1 critical) — Fixed. `pendingResult` mechanism removed. Task 3 calls `result(nil)` immediately for both modes. Task 4's `onCalibrated` emits on EventChannel for both modes, with explicit Dart-side references explaining why.
2. **Float-to-Double casting** (Review 1 suggestion) — Fixed. Task 4 says "Serialize `Float` fields directly without explicit `Double` casting" and cites NfbBridge precedent.
3. **Re-entrancy comment** (Review 1 suggestion) — Fixed. Task 4 includes the instruction to add a code comment about re-entering the SDK from its own callback.
4. **`getCalibration` isCalibrated guard** (Review 2 critical) — Fixed. Task 6 now guards with `clCNFBCalibrator_IsCalibrated(calibrator)` before calling `GetIndividualNFB`, returning `nil` when uncalibrated. The rationale explicitly references the Dart API contract at `nfb_calibrator.dart:272–277`.

## Critical Issues

*None.*

## Suggestions

*None.*

## Positive Notes

- All prior review issues are correctly resolved with clear rationale documented inline.
- Channel IDs (`neiry_kit/nfb_calibrator`, `neiry_kit/events/nfbCalibration`) match both `channel_names.dart` constants and the `NeiryKitPlugin.swift` registration arrays exactly.
- Argument key usage is correct: `args?["calibratorData"]` matches `NeiryArgs.calibratorData` used by both `calibrateIndividual()` (no args → nil → `quick = false`) and `calibrateIndividualQuick()` (`{calibratorData: 'quick'}`).
- Stage advancement emits 0-indexed `currentStage` values that map correctly to `CalibrationStage.fromCode(0)` = `stage1` through `fromCode(3)` = `stage4`.
- The `onCalibrated` event nests data under `{'type': 'done', 'data': dataMap}` matching `CalibrationEvent.deserialize` which reads `map['data'] as Map`.
- The 10 serialization keys (`ts`, `failReason`, `individualFrequency`, etc.) match `IndividualNfbData.fromMap` field-by-field.
- `isCalibrated` and `HasCalibrationFailed` correctly identified as bare-bool returns with no `clCError*` — not wrapped in `do/catch checkCError`.
- Cleanup ordering in Task 7 (`nfbCalibratorBridge?.stopCalibration()` before `nfbBridge?.dispose()`) ensures callbacks are unregistered before the classifier and device are torn down.
- The `isQuickMode` flag is retained solely for its valid purpose (guarding stage advancement in the stage-finished callback) and does not gate EventChannel emission.
- MethodChannel call ordering is safe: Dart sends `stopCalibration` (fire-and-forget) → opens EventChannel → sends `startCalibration`, all dispatched sequentially on the platform thread.

PLAN_REVIEW_PASS
