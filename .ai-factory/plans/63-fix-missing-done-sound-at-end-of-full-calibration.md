# Plan: Fix missing done sound at end of full calibration

## Context
The `playDone()` cue specified in milestone 62 never fires because `_CalibrationCard` is a `ConsumerWidget` (listeners re-register on every rebuild and miss the `loading → data` transition) and because `_running = false` is set synchronously immediately after the awaited state assignment, racing the deferred listener callback so the `isRunning` guard short-circuits. Fix both root causes so full and quick calibration both play the done cue reliably.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Stabilize the listener registration

- [x] **Task 1: Convert `_CalibrationCard` to `ConsumerStatefulWidget`**
  Files: `example/lib/screens/calibration_screen.dart`
  Replace the `_CalibrationCard extends ConsumerWidget` declaration with `_CalibrationCard extends ConsumerStatefulWidget` and add the matching `State<_CalibrationCard> createState() => _CalibrationCardState()` override. Introduce a `_CalibrationCardState extends ConsumerState<_CalibrationCard>` whose `build(BuildContext context)` body contains the existing widget tree, both `ref.listen(calibrationTimerProvider, …)` and `ref.listen<AsyncValue<IndividualNfbData?>>(calibrationProvider, …)` calls, and the `ref.watch(calibrationProvider)` / `ref.watch(calibrationTimerProvider)` calls — unchanged in behavior. The `ref` field on `ConsumerState` is stable across rebuilds, so `ref.listen` registrations persist and the `loading → data` transition is no longer dropped. Do not change the other Consumer widgets in this file (`_IdleContent`, `_ActiveContent`, `_DoneContent`, `_ErrorContent`, `_NfbCard`, `_CalibrationDataCard`) — they don't host listeners and don't need to be converted.

### Phase 2: Close the `_running` race in the notifier

- [x] **Task 2: Defer `_running = false` in `startFull()`** (depends on Task 1)
  Files: `example/lib/providers/calibration_provider.dart`
  In `CalibrationNotifier.startFull()`, replace the synchronous `_running = false;` on line 88 (the line immediately after the `state = await AsyncValue.guard(…)` block) with `Future.microtask(() => _running = false);`. This mirrors the pattern already used by `abort()` for `_aborted` (line 128), so the `ref.listen` callback observing the `loading → data` transition still reads `isRunning == true` and proceeds to `playDone()` / `playError()` instead of early-returning. Keep the subsequent `if (_aborted) return;` guard and `_writeToSharedProvider()` call in their existing order.

- [x] **Task 3: Defer `_running = false` in `startQuick()`** (depends on Task 2)
  Files: `example/lib/providers/calibration_provider.dart`
  In `CalibrationNotifier.startQuick()`, apply the same fix: replace `_running = false;` on line 108 with `Future.microtask(() => _running = false);`. The race is identical — without this change quick calibration also silently skips `playDone()`.

- [x] **Task 4: Update the `_running` doc comment** (depends on Task 3)
  Files: `example/lib/providers/calibration_provider.dart`
  Adjust the doc comment on the `_running` field (lines 27–33) so it reflects the new behavior: the flag is now cleared on a microtask after the terminal state assignment (not synchronously), ensuring `ref.listen` callbacks observing the `loading → data` / `loading → error` transitions still see `isRunning == true`. Keep the note that `importFromFile` and the cold-open `build` path intentionally do not set the flag.
