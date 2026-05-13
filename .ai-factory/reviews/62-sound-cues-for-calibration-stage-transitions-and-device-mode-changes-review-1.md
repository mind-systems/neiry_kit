# Code Review: Sound cues for calibration stage transitions and device mode changes

**Diff scope:** `example/pubspec.yaml`, `example/lib/providers/{calibration_provider,device_state_providers,sound_service_provider}.dart`, `example/lib/screens/{calibration_screen,device_screen}.dart`, plus four new WAV assets under `example/assets/sounds/`.

## Critical

### 1. `if (prev == null) return;` is dead code on `calibrationProvider` — `playDone()` fires on screen open when previous calibration data exists on disk

`example/lib/screens/calibration_screen.dart:50-60`:

```dart
ref.listen<AsyncValue<IndividualNfbData?>>(calibrationProvider, (prev, next) {
  if (prev == null) return; // ignore the initial build emission
  final notifier = ref.read(calibrationProvider.notifier);
  if (notifier.isAborting) return;
  final sound = ref.read(soundServiceProvider);
  if (!prev.hasValue && next.hasValue && next.value != null) {
    sound.playDone();
  } else if (!prev.hasError && next.hasError) {
    sound.playError();
  }
});
```

For an `AsyncNotifierProvider`, `prev` is **never** `null` for a non-`fireImmediately` listener. The comment "ignore the initial build emission" reflects an incorrect understanding of Riverpod semantics. Verified against the Riverpod 3.2.1 source (pinned by `example/pubspec.lock:648`):

- The element's backing field is initialized to `AsyncValue<ValueT>.loading()` (`riverpod-3.2.1/lib/src/core/element.dart:450`) — never `null`.
- All three call sites of `_notifyListeners` pass the prior `_value` (i.e. the most recent non-null `AsyncValue`) as `previousStateValue` (`element.dart:459`, `541`, `602`).
- `FutureModifierElement.resultForValue` always returns `$ResultData(value)` (`riverpod-3.2.1/lib/src/core/modifiers/future.dart:192-194`) — never null for any `AsyncValue` input.
- The listener-dispatch path computes `previousState = previousStateResult?.value` (`element.dart:796`) and forwards it to the listener (`element.dart:842-846`). Combined with the previous two points, the listener's `prev` argument is always a non-null `AsyncValue`.
- The only path that fires the listener with `null` for `previous` is `_handleFireImmediately` (`provider_subscription.dart:382`), which is gated on `fireImmediately: true` (not used here).

Concrete consequence — trace the cold open of the calibration screen:

1. `_CalibrationCard.build` runs. `ref.listen(calibrationProvider, ...)` invokes `_addListener`, which calls `element.flush()` (`provider.dart:117-119`); flush calls `mount()` since `_didMount` is false (`element.dart:637-640`). Mount runs `buildState`, which begins awaiting `NfbCalibrator.getCalibrationData()` and leaves `_value` as `AsyncLoading`.
2. Mount fires `_notifyListeners(value, initialState, isFirstBuild: true, ...)` (`element.dart:541-546`), but with `isFirstBuild: true` the iteration at `element.dart:835` excludes regular `dependents`, so the new listener — which `element.listen` adds via `addDependentSubscription` only **after** `_addListener` returns (`element.dart:931-933`) — is not invoked.
3. After the build frame, the `Future` returned by `NfbCalibrator.getCalibrationData()` resolves. The setter on `_value` runs and calls `_notifyListeners(result, previousResult)` (`element.dart:455-459`), with `previousResult = AsyncLoading` (still the value before set). The listener is now in `dependents` and fires.
4. In our listener: `prev == null` is **false** (it's `AsyncLoading`), `notifier.isAborting` is false, and `!prev.hasValue && next.hasValue && next.value != null` is `true && true && true` whenever `NfbCalibrator.getCalibrationData()` returned a non-null cached calibration (i.e. the common case after the user has previously calibrated).
5. `playDone()` fires.

The same bug fires on the `_ErrorContent` "Retry" path (`calibration_screen.dart:252-257`), which calls `ref.invalidate(calibrationProvider)` — the provider is rebuilt, `build()` re-runs, and the next `AsyncLoading → AsyncData(<cached data>)` transition trips the same condition.

**Required fix.** `prev == null` cannot be the guard. Two viable options:

- **(Preferred)** Track an explicit "calibration was just started by the user" signal in `CalibrationNotifier`. `startFull` and `startQuick` set `_running = true` at the top; `_writeToSharedProvider()` and the error path clear it. The listener gates on `notifier.isRunning` (or equivalent) before firing `playDone`/`playError`. This also naturally excludes `importFromFile`'s `AsyncError → AsyncData` transition, which the current listener *does* fire on (probably not intended either — silent import was the existing behavior).
- **(Quick fix)** Convert `_CalibrationCard` to a `ConsumerStatefulWidget` and hold a `bool _seenFirstEmission = false` in state; skip cues until the first transition observed. Loses the elegance the plan was reaching for, but matches the milestone behavior precisely. (The plan explicitly ruled out converting to `ConsumerStatefulWidget`; reconsider if Option 1 is rejected.)

## Other findings

### 2. `prev == null` in `deviceModeProvider` listener is also dead code — works only because of the second guard

`example/lib/screens/device_screen.dart:170-179`. Same Riverpod semantics apply (`StreamProvider` uses `FutureModifierElement` — see `riverpod-3.2.1/lib/src/providers/stream_provider.dart` chain); `prev` is never null. The cue is correctly suppressed on the first emission only because the inner `if (prev is! AsyncData<NeiryDeviceMode>) return;` short-circuits when `prev` is `AsyncLoading`. The outer `if (prev == null) return;` should be removed or replaced with the meaningful guard pulled out:

```dart
ref.listen<AsyncValue<NeiryDeviceMode>>(deviceModeProvider, (prev, next) {
  if (prev is! AsyncData<NeiryDeviceMode>) return; // suppress first emission after (re)subscribe
  if (ref.read(calibrationProvider).isLoading) return;
  next.whenData((_) => ref.read(soundServiceProvider).playModeChange());
});
```

Functionally equivalent and the intent is no longer hidden behind a check that is structurally always false.

### 3. `Future.microtask(() => _aborted = false)` ordering is correct, but the comment understates the constraint

`example/lib/providers/calibration_provider.dart:106-113`. The fix relies on listener dispatch being synchronous wrt the `state = ...` assignment in `abort()`, which is the case (`element.dart:838-846` invokes the listener via `runBinaryGuarded`, synchronous). Both transitions that abort drives (`loading → error` from `startFull`'s resume, and `error → data` from `abort`'s own assignment) fire their listeners before `abort` returns, so the microtask scheduled at line 113 fires strictly after both. Good.

However: if `abort()` is called when `_fullCompleter` is `null` or already completed (e.g. user races abort with a natural completion, or a future refactor calls `abort()` defensively at teardown), `_aborted` stays `false` for the whole sequence. The post-condition microtask is then a no-op. The `loading → data` and `data → data` transitions in that branch would *not* be suppressed by `isAborting`. The current UI only exposes abort during stage-active, so this is reachable only by completion-race; flag it explicitly in the abort comment or set `_aborted = true` unconditionally at the top of `abort()` for symmetry.

### 4. Stage listener has no `isAborting` guard — works by coincidence, not by design

`example/lib/screens/calibration_screen.dart:44-48`. During `abort()`, the timer is stopped (`calibration_provider.dart:108`), which sets `(elapsed: 0, stage: null)`. `next.stage != null` is false, so `playStageStart()` is correctly skipped. **But** the symmetry of the two listeners would be improved by short-circuiting on `isAborting` here too — a future refactor that changes the timer reset semantics (e.g. preserving the last stage for UI purposes) would silently break the suppression.

### 5. Lost-error visibility on the `.catchError` handlers

`example/lib/providers/sound_service_provider.dart:15-37`. Four near-identical bodies — readable. Two minor nits:

- `Future<void>.catchError` is statically loose (the `Function` argument isn't type-checked). It works here at runtime, but `try`/`catch` with `async` is the codebase's idiom (`calibration_provider.dart:117-132`, `device_screen.dart:107-114`). Aligning would be a small improvement; not blocking.
- The `Object e`/`StackTrace st` parameter typing is fine, but `Object?` is what Dart's `Future` actually passes for error; keeping `Object` works because asserts in `runZonedGuarded` paths never produce null errors, but the analyzer may produce an `avoid_dynamic_calls`/`avoid_catches_without_on_clauses` lint depending on flutter_lints rules.

### 6. `next.whenData` inside `playModeChange` listener — minor

`device_screen.dart:173`. `whenData` callback isn't fired for `AsyncLoading.copyWithPrevious` either, so the disconnect/reconnect path (where Riverpod transitions `AsyncData → AsyncLoading(copyWithPrevious) → AsyncLoading(fresh stream) → AsyncData(firstMode)`) won't accidentally fire on the loading-with-previous intermediate. Confirmed by walking `riverpod-3.2.1/lib/src/core/async_value.dart` — `whenData` matches only `AsyncData`. No issue, just noting.

### 7. `pubspec.yaml` comment cleanup

`example/pubspec.yaml:66`. The `# To add assets to your application, add an assets section, like this:` line is now misleading — the section is no longer an example, it's the live declaration. Either delete the comment or rephrase. Cosmetic, non-blocking.

### 8. Asset directory entry vs. per-file enumeration — recommend keeping the directory form, with a note

The plan opted for `- assets/sounds/`, which is correct and forward-compatible. One thing to be aware of: every file in `example/assets/sounds/` will be bundled, including any future stray files. The directory currently contains only the four required WAVs (verified via `git status`), so this is fine today; just keep in mind for future additions.

## Positive notes

- The `isAborting` getter + microtask reset (`calibration_provider.dart:23-25, 111-113`) is exactly the fix the plan-review asked for, and the listener consults it correctly via `ref.read(calibrationProvider.notifier).isAborting` (`calibration_screen.dart:52-53`).
- `deviceModeProvider` placement and signature (`device_state_providers.dart:10-14`) match the existing `deviceConnectionStateProvider` pattern; `Stream.empty()` fallback when no active device is correct.
- `SoundService` is co-located with its provider in a single file (`sound_service_provider.dart`), matching the codebase's notifier+provider convention.
- The `prev is! AsyncData` guard in the mode-change listener (`device_screen.dart:176`) correctly suppresses the first emission after each `(re)connect → modeChangedStream` subscription, which is the documented intent.
- Stage-advance detection via `next.stage != null && next.stage != prev?.stage` (`calibration_screen.dart:45`) correctly covers both the `null → stage1` initial transition and `stageN → stageN+1` advances, without firing on tick-only state churn (elapsed increments).
- No phantom imports or wrong API surfaces; `AudioPlayer` / `AssetSource` / `play` / `dispose` are the right `audioplayers` 6.x APIs.
- WAV assets are present and tracked (`git status` confirms `example/assets/sounds/{done,error,mode,stage}.wav` are staged).

## Required changes before this can ship

1. **(Critical)** Fix the dead `prev == null` guard in the `calibrationProvider` listener (`calibration_screen.dart:51`). Option 1 (notifier-tracked `isRunning` flag) is preferred; Option 2 (ConsumerStatefulWidget + `_seenFirstEmission`) is acceptable. Without this, opening the calibration screen with previously-cached calibration data — the common case after the first session — plays the "done" cue spuriously, and "Retry" after an error does the same.
2. **(Recommended)** Remove the dead `prev == null` guard in `device_screen.dart:171` and rely on the existing `prev is! AsyncData` check, ideally hoisted out of the `whenData` callback (see snippet in finding #2).
3. **(Recommended)** Either add `isAborting` short-circuit to the stage listener for symmetry, or extend the inline comment to explicitly call out that suppression depends on `timer.stop()` running before the state transition in `abort()`.
