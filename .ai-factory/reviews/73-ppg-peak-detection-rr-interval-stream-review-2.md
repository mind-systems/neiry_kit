# Code Review: PPG peak detection → RR interval stream (round 2)

**Plan:** `.ai-factory/plans/73-ppg-peak-detection-rr-interval-stream.md`
**Spec:** `.ai-factory/notes/23-ppg-rr-interval-stream.md`
**Previous review:** `.ai-factory/reviews/73-ppg-peak-detection-rr-interval-stream-review-1.md`
**Risk:** 🟢 Low — one minor leak path remains; all important findings from round 1 are resolved.

## Resolved since round 1

- ✅ **Dispose race fixed.** `_rrPpgSub` is now a class field (`cardio_classifier.dart:165`) and `dispose()` cancels it explicitly before `_rrController.close()` (`cardio_classifier.dart:277-279`). The `onCancel` callback still cancels it as the secondary path; both ends are idempotent because `_rrPpgSub = null` is set after cancel and `null?.cancel()` is a no-op.
- ✅ **`lastPpiMs` encapsulated.** Renamed to `_lastPpiMs` (`ppg_peak_detector.dart:59`); no longer publicly mutable.
- ✅ **NeiryService formatting.** The new fan-in subscription at `neiry_service.dart:200-203` now uses the multi-line block style with trailing commas, matching its neighbors.

## Findings

### 1. [Minor] Dispose early-return leaks `_rrController` and `_rrPpgSub` when native create failed

**Where:** `lib/src/api/classifiers/cardio_classifier.dart:265-272`

```dart
Future<void> dispose() async {
  if (_disposed) return;
  _disposed = true;
  await _nativeReady;
  if (_createError != null) {
    // Native handle was never created — nothing to destroy.
    return;                       // ← skips _rrPpgSub.cancel() and _rrController.close()
  }
  ...
  await _rrPpgSub?.cancel();
  _rrPpgSub = null;
  await _rrController.close();
}
```

`rrStream`'s getter calls `_checkReady()`, which throws once `_createError` is set — but the underlying create is asynchronous. A consumer that subscribes to `rrStream` *before* the create promise rejects will:

1. Pass the `_checkReady` guard (no error yet).
2. Trigger `onListen` → `_rrPpgSub = _ppgStream.listen(...)`.
3. Later, `_nativeReady` completes with `_createError` populated.
4. When `dispose()` runs it takes the early return, leaving `_rrPpgSub` live on the EventChannel and the broadcast controller open.

Same shape applies to any other state on the class that needs Dart-side cleanup regardless of whether the native handle exists — the early-return comment "nothing to destroy" was accurate when the class only owned a native handle, but the round-1 changes added Dart-side state (`_rrPpgSub`, `_rrController`).

**Severity:** low — window is narrow (subscribe-before-create-rejects) and the platform sub leak is bounded to one EventChannel listener per instance.

**Fix:** move the Dart-side cleanup *before* the early return, or restructure into a `try/finally` so it always runs:

```dart
if (_createError == null) {
  await _channel.invokeMethod<void>(
    ClassifierMethods.dispose,
    {NeiryArgs.serial: _serial},
  );
}
await _rrPpgSub?.cancel();
_rrPpgSub = null;
await _rrController.close();
```

## Verified — no issues

- **Dispose race (round-1 finding 1).** Cancel happens before close; `onCancel` is now a tolerated secondary path. The PPG batch handler can no longer be invoked on a closed controller in the normal `NeiryService.disconnect()` path or in a direct-consumer path.
- **`_rrPpgSub` lifecycle.** Set in `onListen`, cleared in `onCancel`, also cleared in `dispose()`. All accesses are on the single Dart event loop, no real concurrency.
- **`_lastPpiMs` semantics.** Updates only on non-artifact intervals; adaptive refractory cannot collapse from a noise spike.
- **Adaptive refractory transition.** `_lastPpiMs == null` correctly covers both "before first peak" and "between peak 1 and peak 2" states.
- **Both-sides window coverage.** `hasBefore`/`hasAfter` use the captured `bufferFirstMs` / `bufferLastMs`; trailing-edge candidates correctly defer until the next batch supplies right-side samples.
- **Cross-batch peak deduplication.** `!candidate.ts.isAfter(localLastPeak)` filter prevents re-emission of peaks already produced in a prior batch.
- **Buffer eviction anchor.** Uses `batch.timestamps.last` (device clock), avoiding device/system clock drift.
- **`_gate` ordering.** Hard lower bound `rrMs < minRrMs` runs before the cold-start branch, so sub-300 ms spikes cannot poison the rolling median during cold start.
- **Empty-batch / empty-buffer guards.** Early returns prevent `_buffer.first` / `_buffer.last` access on an empty list.
- **Barrel export order.** `rr_interval.dart` placed after `resistance_data.dart` (alphabetical).
- **NeiryService subscription wiring and close order** — `_rrController` declared adjacent to `_cardioPpgController`, closed in matching order in `dispose()`, fan-in cancelled in `disconnect()` before `_cardio!.dispose()` runs.
- **`example/lib/providers/rr_provider.dart`** — minimal, matches the style of `stream_providers.dart`.
- **No native or platform-channel changes.** Pure-Dart addition; iOS/Android bridges, channel constants, and codecs are untouched.
