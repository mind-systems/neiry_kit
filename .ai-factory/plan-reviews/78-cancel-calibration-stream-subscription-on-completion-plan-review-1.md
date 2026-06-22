# Plan Review: Cancel calibration stream subscription on completion

**Plan:** `.ai-factory/plans/78-cancel-calibration-stream-subscription-on-completion.md`
**Target:** `example/lib/providers/calibration_provider.dart`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (ARCHITECTURE.md):** PASS. The change is confined to the example app's Riverpod provider (`example/lib/providers/`), not the plugin's layered SDK bridge (`lib/`, `ios/`, `android/`). No layer/boundary is crossed; the example app is the designated place for end-to-end lifecycle wiring. No violation.
- **Rules (RULES.md):** Present but empty — nothing to enforce. PASS.
- **Roadmap (ROADMAP.md):** WARN (non-blocking). This is a `fix`-class change but the plan does not link it to any roadmap milestone. ROADMAP.md tracks plugin-API milestones, not example-app fixes, so the absence is reasonable — noted only for completeness.
- **skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** Not present. No project-specific review overrides apply.

## Verification of Plan Accuracy

All file paths, line anchors, and API claims were checked against the actual source.

- **File path** `example/lib/providers/calibration_provider.dart` — correct, exists.
- **Task 1 anchor** "around lines 78–82": `CalibrationCompleted(:final data)` is at line 78; completer resolution at lines 80–82. ✅ Accurate.
- **Task 2 anchor** "around lines 85–90": `onError` handler spans lines 85–90; `completeError` at line 88. ✅ Accurate.
- **`ref.onDispose` backstop** "lines 42–45": confirmed at 42–45 (`_sub?.cancel(); _fullCompleter = null;`). ✅
- **`abort()` existing cancel/null**: confirmed at lines 132–133 (`_sub?.cancel(); _sub = null;`). ✅ The plan's instruction to leave it untouched is correct.
- **`startQuick()` needs no change**: confirmed. `startQuick()` (lines 108–123) uses `NfbCalibrator.calibrateIndividualQuick()` (a `Future`, not a stream) and holds no `_sub`. The underlying `calibrateIndividualQuick()` self-cancels its internal subscription on completion (`nfb_calibrator.dart:219–222`). ✅ Claim is accurate.
- **"Cancelling inside the `listen` callback is safe in Dart"**: correct. `StreamSubscription.cancel()` is legal and safe from within the subscription's own callback.

## Diagnosis & Fix Soundness

The fix is correct and the causal mechanism holds up under code reading — and is in fact stronger than the plan's prose suggests:

The provider's `_sub` listens to the `StreamController.stream` returned by `NfbCalibrator.calibrateIndividual()`. That controller has an `onCancel` handler (`nfb_calibrator.dart:161–174`) which, when the current subscription is cancelled, invokes the native `stopCalibration` and cancels the underlying shared-EventChannel subscription (`thisSub`). So cancelling `_sub` after a terminal event does more than free a Dart object: it **tears down the native calibrator and the EventChannel listener immediately**, preventing a lingering native stream from delivering a stale `CalibrationCompleted` into the next run's freshly-subscribed listener. This is the real reason the phantom disappears — and it confirms the plan's verification scenario will pass.

Safety checks on both touched branches:

- **Success branch:** `_fullCompleter!.complete(data)` runs first; the later `await _fullCompleter!.future` resolves from the Completer independently of the (now-cancelled) subscription, so no data is lost. ✅
- **Error branch:** `_fullCompleter!.completeError(...)` runs first; `AsyncValue.guard` still observes the error. ✅
- **Double-cancel:** if a terminal branch nulls `_sub`, the later `abort()` and `ref.onDispose` paths each do `_sub?.cancel()` — a no-op on `null`. Harmless, exactly as the plan states. ✅

No edge cases are left unhandled: the existing `_fullCompleter != null && !_fullCompleter!.isCompleted` guards already prevent double-completion, and the new cancel/null lines do not interfere with them.

## Minor Observations (non-blocking)

1. The plan's Context framing emphasizes the "un-cancelled subscription leak." Note that `NfbCalibrator._cancelActiveCalibration()` (called at the start of every `calibrateIndividual()`) already closes the previous controller, so the old `_sub` would be force-finished on the next run regardless — the leak window is brief. The *actual* curative effect is the prompt `onCancel → native stopCalibration` teardown described above. This does not change any task; the fix is correct as written.
2. Plan setting is "Logging: minimal" and no logging task is included. Acceptable for a two-line teardown fix; the manual verification step is sufficient.

## Positive Notes

- Minimal, surgical change — two lines added to each of two branches, no behavioral rewrite.
- Ordering instruction (resolve completer before cancelling) is precisely correct and prevents a value/error loss bug.
- Plan correctly scopes out `startQuick()`, `abort()`, and the `onDispose` backstop, avoiding redundant or conflicting edits.
- Verification scenario (full calibrate → SDK-rejected re-calibrate) directly exercises the bug path.

PLAN_REVIEW_PASS
