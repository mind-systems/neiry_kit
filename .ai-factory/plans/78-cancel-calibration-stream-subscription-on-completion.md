# Plan: Cancel calibration stream subscription on completion

## Context
Fix the calibration-flow leak where `CalibrationNotifier.startFull()` never cancels its event-channel subscription on terminal events, causing a stale `CalibrationCompleted` from a prior run to fire a phantom "complete" on the next run.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Fix subscription teardown

- [x] **Task 1: Cancel `_sub` in the `CalibrationCompleted` branch**
  Files: `example/lib/providers/calibration_provider.dart`
  In `startFull()`'s `_sub` listener (around lines 78–82), after resolving `_fullCompleter` in the `CalibrationCompleted(:final data)` case, add `_sub?.cancel();` followed by `_sub = null;`. Keep the completer resolution first so `await _fullCompleter!.future` still receives the value. Cancelling inside the `listen` callback is safe in Dart.

- [x] **Task 2: Cancel `_sub` in the `onError` handler**
  Files: `example/lib/providers/calibration_provider.dart`
  In `startFull()`'s `onError` handler (around lines 85–90), after `_fullCompleter!.completeError(error, stack)`, add `_sub?.cancel();` followed by `_sub = null;`. Keep the completer error resolution first. Do not alter the `ref.onDispose` backstop (lines 42–45) or `abort()`'s existing cancel/null — nulling `_sub` here just prevents a harmless double-cancel.

## Verification

Run a full calibrate, then trigger a re-calibrate that the SDK rejects. Confirm no phantom "Calibration complete — data received" carrying prior-run data is logged after the error. `startQuick()` already self-cancels and needs no change.
