# Plan Review: Migrate classifiers_screen, mems_screen, productivity_cardio_screen

Plan: `.ai-factory/plans/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen.md`

## Verification

I read the plan and cross-checked every claim against the current codebase:

- `example/lib/services/neiry_service.dart` — confirmed all controllers, classifier construction, and `_activeSubscriptions` fan-in pattern match what the plan asserts. The two existing `calibrationProgress` `listen()` entries (lines 212–219) are the exact anchor the plan extends. Closing controllers in `dispose()` only (not `disconnect()`) is the established pattern.
- `lib/src/api/classifiers/physio_classifier.dart` — `Stream<PhysiologicalStatesBaselines> get calibrated` exists at line 145 and is safe to subscribe to immediately after construction (`_checkNotDisposed` / `_checkReady` both pass).
- `lib/src/api/classifiers/cardio_classifier.dart` — `Stream<void> get calibratedStream` exists at line 195 with the same guards. Both subscriptions become valid as soon as the classifier is constructed.
- `example/lib/providers/classifier_stream_providers.dart` — current shape and grouping confirmed; placement of the two new providers between `productivityCalibrationProgressProvider` and `physioBaselinesProvider` is consistent.
- `example/lib/providers/nfb_calibration_provider.dart` — already imports `flutter_riverpod/legacy.dart`, so `StateProvider` is in scope for the two new toggles.
- `example/lib/providers/physio_actions_provider.dart` and `productivity_actions_provider.dart` — both expose the exact method names the plan invokes (`startBaselineCalibration`, `importBaselines`, `resetAccumulatedFatigue`), both no-op when no device is connected, both are `NotifierProvider<…, void>`.
- All three screens — every symbol the plan claims to remove or rewrite was verified at the cited locations. All `log(…, name: 'Neiry')` call sites are exactly where the plan says.

The plan's roadmap context (milestones 88, 90, 91, 92, 94) lines up with the actual `.ai-factory/ROADMAP.md` entries.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)**: ✅ no violations. Edits stay in `example/` and use only the public `neiry_kit` barrel API. Dependency rule `example/ → lib/` is respected.
- **Rules**: no `.ai-factory/RULES.md` and no `.ai-factory/skill-context/aif-review/SKILL.md` in this repo. No project-specific overrides to apply.
- **Roadmap (`.ai-factory/ROADMAP.md`)**: ✅ this work is the unchecked milestone 93 (line 93). Scope matches the roadmap description, and Task 7 explicitly defers `calibration_screen.dart` to milestone 94.

## Critical Issues

None. The plan correctly identifies the missing service surface (the two calibration-completion streams), adds it in the established controller pattern, and only then re-creates the providers and migrates the screens.

## Should Fix

### 1. Unused-import removal must be mandatory, not "consider"

Tasks 5 and 6 both phrase the cleanup of `device_state_providers.dart` as "consider removing". After deleting the `uiState` / `canEditToggle` references, that import is unused, which Dart's analyzer flags as `unused_import` — and Task 7 calls for a clean `flutter analyze`. The two tasks should state outright: "Remove `import '../providers/device_state_providers.dart';` — it has no remaining references." Leaving it as a suggestion creates an analyzer warning that the verification step is expected to be clean of.

### 2. Buttons become always-visible — silent no-op when disconnected

After Tasks 4 and 6, the three Physio action buttons and the two Productivity action buttons are unconditional children of their cards. The underlying notifier methods are intentional no-ops when `physioClassifier`/`productivityClassifier` is null. UX consequence: a user taps "Start Baseline Calibration" with no device connected and gets no visible response (no SnackBar, no state change). The current code hides those buttons until a classifier exists.

This is a minor regression. Two options worth considering:
- Wrap each button's `onPressed` in a guard: `final connected = ref.watch(deviceConnectionStateProvider).valueOrNull == NeiryConnectionState.connected;` and pass `onPressed: connected ? () { … } : null` to grey them out.
- Or accept the regression and explicitly note it in the plan as deliberate, so the next milestone doesn't treat it as a bug.

The plan currently does neither — it just asserts the buttons "are always visible" without addressing the no-op tap behavior.

### 3. Stale-data persistence after disconnect (informational)

This is a system-wide consequence of the milestone-90 stream-provider migration, not unique to this plan, but worth flagging because the plan leans on it: after disconnect, `_activeSubscriptions` is cancelled but the broadcast controllers stay open. A `StreamProvider` watching such a controller retains its **last** `AsyncValue.data(...)` indefinitely; it does not revert to `AsyncValue.loading()`. So after a connect → some data → disconnect cycle, the Emotions/Physio/Cardio/MEMS cards will keep showing the last frame of data instead of "Waiting for device...".

The plan's wording in Task 4 ("Riverpod treats a StreamProvider watching a stream that has not yet emitted as loading") is correct only for the *first* connect attempt of the app's lifetime. After any successful connect, the loading branch never fires again.

This is acceptable as long as the team knows. If it's not acceptable, the fix belongs at the `NeiryService` level (e.g., emit a sentinel "cleared" value on disconnect, or invalidate the providers on disconnect) — not inside the screens, and probably not inside this milestone.

## Nice to Have

### 4. Task 3 dependency on Task 2 is unnecessary

Task 3 (add two `StateProvider<bool>` toggles in `nfb_calibration_provider.dart`) has no code-level dependency on Task 2 (add two `StreamProvider`s in `classifier_stream_providers.dart`). They edit different files and reference different APIs. The dependency arrow doesn't block correctness — both must land before Phase 3 — but it falsely implies a code coupling. Marking Task 3 as depending on Task 1 (or on nothing) would be more accurate.

### 5. `_safeProductivityWithCalibration` is unchanged — confirm intent

`NeiryService.connect` already routes around the `UnsupportedError` from `ProductivityClassifier.withCalibration` via a private fallback helper (line 399). No analogous fallback exists for `CardioClassifier.withCalibration` or `MEMSClassifier.withCalibration` (lines 139–144). This is out of scope for the current plan, but if either Cardio or MEMS `withCalibration` constructors ever throw `UnsupportedError`, the new `_cardioCalibratedStream` subscription will fail at construction and propagate. Not a blocker — just worth noting as a follow-up.

### 6. Preserve-everything-else implication should be explicit

Task 4 says "Keep all four `log('Physio: …', name: 'Neiry')` calls byte-identical" and "Keep `ref.listen(physioCalibratedProvider, …)` unchanged" but does not call out preservation of:
- The Import Baselines SnackBar (`'Baselines imported'`)
- The Export Baselines path-display SnackBar
- The `baselines == null ? null : …` disabled-state guard on Export Baselines

These are implicit ("only edits the things the task names") but easy to miss during execution. A one-line "All other widget content, SnackBars, and disabled-state guards on these buttons are preserved verbatim" would tighten Tasks 4–6.

## Positive Notes

- The plan correctly identifies the **one** gap in `NeiryService` (missing calibration-completion stream surface) and fixes it as Phase 1 before any provider or UI work. This is exactly the right ordering.
- Listening to `_physio!.calibrated` and `_cardio!.calibratedStream` is wired through `_activeSubscriptions`, so cancellation on disconnect is automatic — no leak.
- Controller close ordering in `dispose()` (after the two progress controllers) matches the surrounding pattern.
- The toggle providers are correctly framed as pure preference flags (no device dependency, no side effects) — this is the right model now that calibration data is a connect-time decision (per milestone 88).
- Task 7's explicit "if the analyzer flags X outside the four expected files, stop and report — that belongs to milestone 94" is good defensive guidance and keeps scope tight.
- Commit plan is well-segmented: infrastructure (controllers + providers + toggles), then screens, then verify.

---

The plan is sound. The Should-Fix items are wording tightness and a minor UX guard, not correctness issues. Tasks 1–7 can be executed in order as written.

PLAN_REVIEW_PASS
