# Code Review: NfbCalibrator (Round 2)

**Plan:** `.ai-factory/plans/14-nfbcalibrator.md`
**Files reviewed:** `lib/src/api/nfb_calibrator.dart`, `lib/neiry_kit.dart`

## Round 1 Fixes Verified

All three critical issues and the suggestion from round 1 have been addressed:

1. ✅ **`onCancel` guarded with `wasCurrent`** (line 155) — native `stopCalibration` is only invoked when `_calibrationSubscription` still points to `thisSub`. A late cancel from an old consumer no longer kills a newer calibration.

2. ✅ **`_quickCompleter` tracked and failed on external cancel** (lines 48, 72-75) — `_cancelActiveCalibration()` completes the `Completer` with `StateError('Calibration cancelled')` so the returned Future no longer hangs on `stopCalibration()` or overlap.

3. ✅ **All fire-and-forget `stopCalibration` calls have `.catchError((_) {})`** (lines 98-99, 160-161, 183-185) — no more unhandled Future rejections.

4. ✅ **`_calibrationController` tracked and closed on external cancel** (lines 53, 66-70) — the consumer stream from `calibrateIndividual()` now receives a done event when `stopCalibration()` or overlap fires. This was the round 1 suggestion, also fixed.

## Scenario Traces

Verified the following runtime scenarios produce correct behavior:

- **Normal full calibration** — events flow through controller, `onDone` closes it.
- **Normal quick calibration** — `CalibrationCompleted` resolves the completer, subscription cancelled.
- **Overlap full → full** — old controller closed (consumer gets done), old subscription cancelled, new calibration proceeds unaffected. Old consumer's late `onCancel` does NOT fire native stop (`wasCurrent` is false).
- **Overlap quick → full** — old completer failed with `StateError`, new stream works.
- **Overlap full → quick** — old controller closed, new completer works.
- **`stopCalibration()` during full** — controller closed, native stop awaited.
- **`stopCalibration()` during quick** — completer failed, native stop awaited.
- **`startCalibration` MethodChannel fails (full)** — error forwarded to controller, controller closed.
- **`startCalibration` MethodChannel fails (quick)** — error forwarded to completer.
- **`startCalibration` fails + concurrent `stopCalibration()`** — `completer.isCompleted` guard prevents double-complete.
- **`controller.close()` triggers deferred `onCancel`** — `_calibrationSubscription` already nulled by `_cancelActiveCalibration()`, so `wasCurrent` is false, no stale native stop.

## Critical Issues

None.

## Positive Notes

- The `_cancelActiveCalibration()` helper (lines 62-76) cleanly centralizes all Dart-side cleanup — subscription, controller, and completer — with idempotent null/closed guards. Both calibration methods and `stopCalibration()` delegate to it, eliminating the previous code duplication.
- The `clearIfCurrent()` closures in both methods now clear both the subscription AND the controller/completer static fields (lines 110-117, 195-202), preventing stale references after natural completion.
- The `wasCurrent` pattern in `onCancel` (line 155) is the correct minimal fix — it preserves the "consumer cancel stops native calibration" behavior for the active calibration while avoiding cross-talk on overlap.
- Doc comments accurately describe the new cancellation semantics (`stopCalibration` doc at lines 248-253, `calibrateIndividualQuick` throws clause at lines 174-176).

REVIEW_PASS
