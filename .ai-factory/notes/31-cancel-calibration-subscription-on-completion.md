# Cancel calibration stream subscription on completion

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- `CalibrationNotifier.startFull()` subscribes to `NfbCalibrator.calibrateIndividual()` via `_sub` but **never cancels it** on `CalibrationCompleted` — cancellation happens only in `ref.onDispose`. The subscription from a completed run is abandoned (overwritten by the next `startFull`) without being cancelled.
- This leaks an event-channel subscription and produces a **phantom completion**: on the next run a stale `CalibrationCompleted` carrying the *previous* run's `IndividualNfbData` is delivered, so right after a failed re-calibrate the UI/logs report a "complete" with the old timestamp and values.
- Observed in logs: a failing recalibrate (error `Calibration has already been started`) was immediately followed by a "Calibration complete — data received" carrying the prior run's data (`timestamp 19:11:30.384`).
- This is a calibration-flow correctness bug, independent of the native locator fix ([[29-recreate-locator-session-on-disconnect]]) and the UI reset ([[30-reset-calibration-ui-state-on-disconnect]]).

## Details

### Current state

`example/lib/providers/calibration_provider.dart`, `startFull()`:
```dart
_sub = NfbCalibrator.calibrateIndividual().listen(
  (event) {
    switch (event) {
      case CalibrationStageFinished(:final stage):
        if (stage.code < 3) {
          timer.startStage(CalibrationStage.fromCode(stage.code + 1));
        }
      case CalibrationCompleted(:final data):
        timer.stop();
        if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
          _fullCompleter!.complete(data);          // <-- _sub NOT cancelled
        }
    }
  },
  onError: (error, stack) {
    timer.stop();
    if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
      _fullCompleter!.completeError(error, stack); // <-- _sub NOT cancelled
    }
  },
);
```
`_sub` is only cancelled in `build()`'s `ref.onDispose`. `abort()` does cancel `_sub`.

### Exact change

`_sub` field declared at `calibration_provider.dart:16` (`StreamSubscription<CalibrationEvent>? _sub;`). Cancel and null it once the full run reaches a terminal state, in both the `CalibrationCompleted` branch (`calibration_provider.dart:67`) and the `onError` handler (`:74`):
```dart
case CalibrationCompleted(:final data):
  timer.stop();
  if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
    _fullCompleter!.complete(data);
  }
  _sub?.cancel();
  _sub = null;
```
```dart
onError: (Object error, StackTrace stack) {
  timer.stop();
  if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
    _fullCompleter!.completeError(error, stack);
  }
  _sub?.cancel();
  _sub = null;
},
```

### Guards / pitfalls

- Cancelling inside the `listen` callback is safe in Dart. Null `_sub` afterward so `abort()`/`onDispose` do not double-cancel (harmless but tidy).
- Do not cancel before completing `_fullCompleter` — keep the completer resolution first so `startFull`'s `await _fullCompleter!.future` resolves with the correct value/error.
- `startQuick()` already cancels its own subscription on completion (`thisSub.cancel()` inside `calibrateIndividualQuick`), so only the full path needs this.
- Keep the `ref.onDispose` cancel as a backstop.

### Verify

Run full calibrate, then trigger a re-calibrate that the SDK rejects (e.g. before fix 29 lands). Expect no phantom "Calibration complete — data received" with prior-run data after the error.

## Open Questions

None.
