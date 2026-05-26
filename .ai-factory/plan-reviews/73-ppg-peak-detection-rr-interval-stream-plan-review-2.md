# Plan Review (iteration 2): PPG peak detection → RR interval stream

**Plan:** `.ai-factory/plans/73-ppg-peak-detection-rr-interval-stream.md`
**Spec:** `.ai-factory/notes/23-ppg-rr-interval-stream.md`
**Prior review:** `.ai-factory/plan-reviews/73-ppg-peak-detection-rr-interval-stream-plan-review-1.md`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — WARN. The plan introduces a new `lib/src/processing/` directory that is not in the ARCHITECTURE.md folder layout (which lists only `api/`, `models/`, `channel/`). Acceptable as a one-off pure-Dart DSP sibling, but ARCHITECTURE.md should be amended in a separate housekeeping task if more DSP utilities are expected (filters, downsamplers, HRV math). Non-blocking.
- **Rules (`.ai-factory/RULES.md`)** — N/A, file not present.
- **Roadmap (`.ai-factory/ROADMAP.md`)** — N/A (numbered plan 73 follows the established convention; the spec note 23 documents the milestone rationale).

## Resolution of Prior Review Items

All seven points from review 1 are now addressed in the plan text:

1. **Alphabetical export order (Task 3)** — Fixed. The plan now says "after `resistance_data.dart` (which is currently the last `src/models/*` export)" and includes the `'e' < 'r'` justification. Verified against `lib/neiry_kit.dart` (line 33).
2. **Buffer eviction anchor (Task 2 step 2)** — Fixed. Now anchored on `batch.timestamps.last`, with rationale about device-clock vs system-clock drift. Empty-batch early-return (`if (batch.values.isEmpty) return const [];`) is added in step 1, which makes `batch.timestamps.last` safe.
3. **Adaptive refractory transition (Task 2 step 4)** — Fixed. Explicit three-phase rule: pre-first-peak = 250 ms, between peak 1 and peak 2 = still 250 ms, post-second-peak = `(0.55 * lastPpiMs).round()`.
4. **Refractory not updated on artifact PPIs (Task 2 step 5)** — Fixed. "When artifact: do NOT touch `_rrHistory` or `lastPpiMs`."
5. **Both-sides window coverage (Task 2 step 3, clause b)** — Fixed. Candidate must have `_currentRefractory / 2` ms of samples both **before** AND **after** with an explicit rationale about trailing-edge false positives.
6. **`asBroadcastStream()` re-listen (Task 4)** — Fixed. Replaced with an explicit `StreamController.broadcast` backed by an `onListen`/`onCancel` pair that re-creates the source subscription cleanly.
7. **`reset()` on `PpgPeakDetector` (Task 2)** — Added, with semantics described and the note that the integration in Task 4 does not yet call it.

## Critical Issues

None.

## Important Issues

None.

## Minor / Style

### 1. `dispose()` ordering when native create failed (Task 4)

`CardioClassifier.dispose()` (lines 207–219) **returns early** when `_createError != null`:

```dart
await _nativeReady;
if (_createError != null) {
  return;
}
await _channel.invokeMethod<void>(ClassifierMethods.dispose, ...);
```

The plan says "Close `_rrController` inside `dispose()` after the existing native dispose call." Read literally, this places the close after `invokeMethod`, **inside** the post-error-check branch — so if native create failed, `_rrController` is never closed. In practice this is a near-no-op (the rrStream getter throws via `_checkReady`, no listener ever attached, no source subscription opened), but a leaked broadcast controller is still untidy.

Recommendation: make Task 4 explicit that the close happens regardless of `_createError`, e.g. by moving it before the `if (_createError != null) return;` line, or by adding an `unawaited(_rrController.close());` before the early return.

### 2. Existing `NeiryService.dispose()` close order is not strictly declaration order

Task 5's wording assumes "declaration order and close order stay in lockstep" as a convention. That assumption isn't fully true today — `_artifactsController` is declared between `_psdController` and `_resistanceController` but is closed after `_batteryController` (`neiry_service.dart` lines 53 vs 332). Placing `_rrController.close()` immediately after `_cardioPpgController.close()` is still the correct call (it matches the declaration adjacency to `_cardioPpgController`), so the resulting code is correct — only the justifying comment in the plan is slightly idealised. Non-blocking.

### 3. `dispose()` close list also needs `_cardioCalibratedController`-style consistency

`NeiryService.dispose()` already closes every existing controller. Just confirm during implementation that the new `_rrController.close()` is added (the plan says so but the diff is small enough to be missed in review). Pure reminder.

### 4. Doc comment redundancy

Both `RRInterval` (Task 1) and `CardioClassifier.rrStream` (Task 4) are required to carry the "wall-clock `DateTime`, not monotonic" warning. Mild duplication, but acceptable for discoverability (consumers may read either site first).

## Architectural / Cross-cutting Notes

- **Pure-Dart, no native changes.** Confirmed: no edits to `lib/src/channel/`, `ios/`, `android/`, or the C SDK. `PpgPeakDetector` imports only `models/ppg_data.dart` and `models/rr_interval.dart`. ✅
- **Encapsulation.** `PpgPeakDetector` is intentionally not exported from `neiry_kit.dart`. Good — it's an implementation detail.
- **No migrations, no security surface.** Pure local DSP over an existing in-process stream.
- **`lib/src/processing/` is new.** Created on first file write; no scaffolding task needed. See ARCHITECTURE context gate above.

## Positive Notes

- All seven prior-review concerns are addressed in the plan text, with explicit rationale alongside each correction rather than silent edits. The implementer can read the plan top-to-bottom and pick up the "why."
- The `StreamController.broadcast` pattern in Task 4 (with `onListen` opening the source subscription and `onCancel` tearing it down) is the right shape for a derived broadcast stream and matches how `mind_mobile` will likely subscribe/unsubscribe across screens.
- The peak-detection conditions (a/b/c) are now precisely specified — particularly the both-sides window coverage requirement that prevents the trailing-sample false positive.
- `lastPpiMs` (and therefore `_currentRefractory`) gated by `!isArtifact` correctly prevents a 100 ms spike from collapsing the refractory and unlocking a cascade.
- `reset()` exposed but not called yet — the consumer (mind_mobile) can opt in for stop/start cycles. Right level of abstraction.
- Provider follows existing example-app idioms (`stream_providers.dart` style), and the "no throttle" decision is justified against worst-case rebuild rate.

## Recommended Plan Revisions Before Implementation

1. **Minor — Task 4 dispose ordering.** Specify that `_rrController.close()` runs even on the `_createError != null` early-return path (or move the close above the early return). Otherwise a leaked-but-unused broadcast controller in the create-failed case.

Nothing else blocking. The plan is ready for implementation.

PLAN_REVIEW_PASS
