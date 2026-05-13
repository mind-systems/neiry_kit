# Code Review (Round 2): Sound cues for calibration stage transitions and device mode changes

**Diff scope:** unchanged set from round 1 (`example/pubspec.yaml`, three provider files, two screen files, four new WAV assets). The code in those files has been revised since review-1 to address every blocking finding.

## Verification of round-1 findings

### 1. Critical: dead `prev == null` guard on `calibrationProvider` listener — **FIXED**

`CalibrationNotifier` now tracks an explicit `_running` flag (`calibration_provider.dart:27-36`) that is set to `true` at the top of `startFull` and `startQuick` (lines 51, 97) and cleared on the line immediately after `state = await AsyncValue.guard(...)` (lines 88, 108). The widget listener at `calibration_screen.dart:51-61` now gates on `notifier.isRunning` instead of `prev == null`. Walked the relevant scenarios:

- **Cold open with cached calibration data on disk.** Provider mounts; `build()` returns existing data. State goes `AsyncLoading → AsyncData(cachedData)`. Listener fires; `isRunning` is `false` (build doesn't set it); listener returns. ✓ The previously-spurious `playDone()` is now suppressed.
- **Retry button.** `ref.invalidate(calibrationProvider)` rebuilds the notifier; `_running` initializes to `false`; same path as cold-open. ✓
- **`importFromFile`.** Path explicitly excluded by docstring (lines 30-32). `AsyncError → AsyncData(importedData)` and `AsyncData → AsyncData(importedData)` both skip via `!isRunning`. ✓
- **Happy-path full calibration.** `_running = true`, state goes `AsyncData(prev) → AsyncLoading → AsyncData(newData)`. The crucial detail is that `_running = false` runs **after** `state = await AsyncValue.guard(...)`. Riverpod's listener dispatch is synchronous within the setter (`element.dart:838-846` in riverpod-3.2.1 — `runBinaryGuarded` is synchronous), so the listener observes `isRunning == true` and fires `playDone()` correctly. `_running = false` runs on the next synchronous line. ✓
- **Calibration error.** Same as above, but the listener takes the `!prev.hasError && next.hasError` branch and fires `playError()`. ✓

The line ordering `state = await ...; _running = false;` is load-bearing. A passing comment in the code is **strongly recommended** ("clearing must follow the state assignment so the synchronous listener dispatch sees `isRunning == true`"), since the docstring at lines 27-33 documents intent but not the synchronous-dispatch contract that holds it together. Anyone reordering these two lines in the future would silently break the cue. **Not blocking** — the docstring partially covers it — but worth tightening.

### 2. Dead `prev == null` guard on `deviceModeProvider` listener — **FIXED**

`device_screen.dart:170-174` now reads:

```dart
ref.listen<AsyncValue<NeiryDeviceMode>>(deviceModeProvider, (prev, next) {
  if (prev is! AsyncData<NeiryDeviceMode>) return; // suppress first emission after (re)subscribe
  if (ref.read(calibrationProvider).isLoading) return; // calibration owns audio
  next.whenData((_) => ref.read(soundServiceProvider).playModeChange());
});
```

Matches the suggested refactor from review-1: dead `prev == null` removed, intent guard hoisted. ✓

### 3. Stage listener missing `isAborting` guard — **FIXED**

`calibration_screen.dart:44-49` now consults `isAborting` first. The previous coincidental safety (timer.stop() in abort sets stage to null before any state transition) is now belt-and-braces. ✓

## New findings on the revised code

### 4. `_running` is not cleared if `startFull`/`startQuick` throws synchronously before the `await AsyncValue.guard` (minor)

`AsyncValue.guard` traps errors inside its callback, so the assignment `state = await AsyncValue.guard(...)` itself shouldn't throw. But `await WakelockPlus.enable()` (line 52, 98) runs **before** any error trapping, and `ref.read(calibrationTimerProvider.notifier)` (line 56) could in principle throw. If anything between `_running = true` and `state = await AsyncValue.guard(...)` throws, `_running` is permanently stuck at `true` until the next call to `startFull`/`startQuick` resets it — and during that window, any state transition (e.g. an `importFromFile` invocation) would erroneously fire cues.

Defense: wrap the body in `try/finally`:

```dart
_running = true;
try {
  await WakelockPlus.enable();
  ...
  state = await AsyncValue.guard(...);
} finally {
  _running = false;
}
```

Probability of an exception slipping through this narrow window is very low (and `WakelockPlus.enable()` is generally infallible). **Recommended, not required.**

### 5. `prev!` force-unwrap on line 56 — works, but inconsistent with the explicit nullability check on line 46

`calibration_screen.dart:56`: `if (!prev!.hasValue && next.hasValue && next.value != null) {`. Verified against riverpod-3.2.1 source (`element.dart:450, 459, 541, 602` and `core/modifiers/future.dart:192-194`) that `prev` is never `null` for a non-`fireImmediately` `ref.listen` on `AsyncNotifierProvider`, so this is sound. But:

- The stage listener three lines above (`calibration_screen.dart:46`) uses the safer `prev?.stage` form for `NotifierProvider`, where the same guarantee applies.
- Future maintainers reading just `prev!` won't know whether it's safe; the type signature says it could be null.

The static-analyzer-friendly form would be either:
- An assertion: `assert(prev != null, 'AsyncNotifierProvider always passes non-null prev for non-fireImmediately listen');` followed by the bang, or
- A guard at the top of the listener (`if (prev == null) return;`) — which would be dead code per round 1, but the `isRunning` early-return already implicitly excludes the only would-be-null case (initial subscription with no state).

Cosmetic; **non-blocking.** If touching, the assertion form documents the invariant.

### 6. Abort during a quick calibration (`startQuick` + concurrent `abort`) would fire `playDone` — edge case, currently unreachable

If `abort()` is invoked while `startQuick` is mid-flight:

1. `_fullCompleter` is null → the early `if` block in `abort` is skipped → `_aborted` stays `false`.
2. `abort` reaches `state = AsyncValue.data(await NfbCalibrator.getCalibrationData())`.
3. The listener fires. `isRunning == true` (quick is still running), `isAborting == false`. If `prev` was `AsyncLoading` and `next` is `AsyncData(non-null)`, **`playDone()` fires** unintentionally.
4. `startQuick` then completes, sets state to the quick result, listener doesn't fire (prev had value).

The UI doesn't currently expose an abort button during quick calibration (`_ActiveContent` only renders for stage-active state, which quick never enters — `calibration_timer_provider.dart` never tracks quick). So this is **theoretically reachable only via direct notifier access**. Worth a one-line guard for symmetry, or a comment in `abort()` noting that the abort path assumes only `startFull` is interruptible.

### 7. `audioplayers` interrupt semantics + `.catchError` — accepted in plan, but verify on first device run

`SoundService` uses a single shared `AudioPlayer` and calls `.play(AssetSource(...))` four ways. The plan's Design Decisions section explicitly accepts cue truncation when two cues fire close together. On the calibration happy path, the worst realistic overlap is `playStageStart()` (for stage 4 entry) followed shortly by `playDone()` (when stage 4 finishes and `CalibrationCompleted` fires). The gap is bounded by stage 4's duration (multiple seconds), so truncation is unlikely. The mode-change cue is guarded against firing during calibration. **No code change needed**; flag this for the on-device test pass.

`.catchError` on `Future<void>` with a `void`-returning handler is statically permissive (the parameter is `Function`, not strongly typed), and works at runtime. **No change needed.**

### 8. `state = AsyncValue.data(await NfbCalibrator.getCalibrationData())` in `abort()` — defensive note

If `NfbCalibrator.getCalibrationData()` throws (rather than returning null), `abort` propagates the exception up to its caller (the UI button handler), and `state` stays at the `AsyncError` that `startFull` already wrote on the loading→error edge. `_aborted` is never cleared (the `Future.microtask` on line 128 never queues). Listeners would still skip cues for the error transition (isAborting was true at the moment of state assignment), but `_aborted == true` persists indefinitely, and any subsequent transition that uses `isAborting` for suppression would silently mute itself.

The pre-existing assumption that `getCalibrationData()` never throws is reasonable, but this is a slightly worse blast radius than before (since `isAborting` is now a public contract). **Recommended (small):** wrap the final `state = ...` in a `try/finally` (or do the read first, then assign):

```dart
final IndividualNfbData? latest;
try {
  latest = await NfbCalibrator.getCalibrationData();
} finally {
  Future.microtask(() => _aborted = false);
}
state = AsyncValue.data(latest);
```

Or simpler — move the microtask schedule before the await:

```dart
ref.read(calibrationTimerProvider.notifier).stop();
await WakelockPlus.disable();
final latest = await NfbCalibrator.getCalibrationData();
state = AsyncValue.data(latest);
Future.microtask(() => _aborted = false);
```

(Equivalent to current behaviour for the happy path, and the reset still runs even if `getCalibrationData` threw — though in that case the throw would still propagate and we'd want to set state to error explicitly.) **Non-blocking.**

## Positive notes

- All three round-1 fixes (notifier-tracked `isRunning`, `prev is! AsyncData` on mode-change, `isAborting` symmetry on stage listener) are correctly implemented.
- `_running` docstring (`calibration_provider.dart:27-33`) explicitly enumerates what triggers it and what doesn't (`importFromFile`, cold-open `build`), so the next maintainer touching `importFromFile` or adding a new entrypoint has a clear policy.
- Listener invocation order works out: the synchronous setter on `state = ...` reaches `_notifyListeners`, which dispatches the listener via `runBinaryGuarded` synchronously *before* the next statement in `startFull`/`startQuick`/`abort` runs. Confirmed against `riverpod-3.2.1/lib/src/core/element.dart:452-461, 838-846`.
- The `prev is! AsyncData` guard in `device_screen.dart:171` correctly suppresses the per-connect first emission for `StreamProvider<NeiryDeviceMode>`, and `whenData` won't fire on `AsyncLoading.copyWithPrevious` transitions during disconnect/reconnect, so no false beeps on the lifecycle edges.
- No phantom imports, no missing assets, asset directory entry (`assets/sounds/`) bundles the four WAVs that are git-tracked.

## Summary

All blocking findings from round 1 are addressed. Remaining items are minor — finding #4 (lost `_running = false` if the synchronous prelude throws) and finding #8 (lost `_aborted = false` reset if `getCalibrationData()` throws) are robustness concerns with very low probability of triggering in practice. Findings #5 (`prev!` cosmetic) and #6 (abort during quick — unreachable via UI) are non-blocking.

REVIEW_PASS
