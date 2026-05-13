# Plan Review: Sound cues for calibration stage transitions and device mode changes

**Plan:** `.ai-factory/plans/62-sound-cues-for-calibration-stage-transitions-and-device-mode-changes.md`
**Risk Level:** 🟡 Medium

## Summary

The plan faithfully follows the roadmap milestone description (assets exist, audioplayers wired through Riverpod, listeners on `calibrationTimerProvider`/`calibrationProvider`/new `deviceModeProvider`). File paths, API surfaces (`device.modeChangedStream`, `NeiryDeviceMode`, `CalibrationStage`, `IndividualNfbData`), and provider locations all line up with the actual codebase. However, two of the listener strategies don't match the runtime behavior they're supposed to produce, and several minor decisions diverge from existing project patterns without justification.

## Context Gates

- **ARCHITECTURE.md:** present. The plan stays inside the `example/` app and doesn't touch the plugin surface, so no boundary violation. WARN: the milestone was previously labelled "no audio package exists in `example/pubspec.yaml`" — that's still accurate. No alignment issue.
- **RULES.md:** not present. No project-rules gate to run.
- **ROADMAP.md:** present. Milestone (line 83) matches plan steps 1‑1 — including the questionable choices (split files, ConsumerStatefulWidget conversion) which originate in the roadmap text itself.
- **`.ai-factory/skill-context/aif-review/SKILL.md`:** absent — no project overrides apply.

## Critical Issues

### 1. The "ignore abort" requirement is not actually achieved by Task 4's listener
The roadmap says explicitly *"do not play on idle or abort"*. The plan acknowledges the gap (Task 4 note: "abort … must be ignored per the milestone spec — but the spec explicitly lists error firing only for the `!prev.hasError → next.hasError` edge, which naturally covers a fresh error after loading") and then ships a listener that **will fire on abort**. Walking the existing `CalibrationNotifier.abort()` flow (`example/lib/providers/calibration_provider.dart:96‑107`) against the listener in Task 4:

1. User taps "Abort" while `state == AsyncLoading`.
2. `_fullCompleter.completeError(StateError('Calibration aborted'))` fires.
3. The `await AsyncValue.guard(...)` inside `startFull` (line 65) catches that error and assigns `state = AsyncError(...)`. This is the transition `prev.hasError == false (loading) → next.hasError == true` → **`playError()` fires.** ❌
4. After `await WakelockPlus.disable()`, `abort()` runs `state = AsyncValue.data(await NfbCalibrator.getCalibrationData())` (line 106). If `getCalibrationData()` returns a non-null value (which is the common case after a previous successful calibration), this is the transition `!prev.hasValue (error) → next.hasValue && next.value != null` → **`playDone()` fires.** ❌

So a single abort produces **error sound + done sound** in sequence — exactly what the milestone says must not happen.

This is the highest-priority correctness defect. Acceptable fixes (pick one and document it):

- Have `CalibrationNotifier.abort()` set an `_isAborting` flag (or expose a one-shot signal/event) that the listener checks before firing either cue, then clears it.
- Cancel the `_fullCompleter` future without surfacing it through state (e.g. set `_aborted` first, then in `startFull`'s `AsyncValue.guard` check `_aborted` and return the previous value instead of letting the error propagate).
- Have abort assign `AsyncValue.data(previousValue)` directly without the intermediate error transition, and gate the listener on a transient "aborting" state.

Whichever fix is chosen, **Task 4 must amend `CalibrationNotifier`**, not just the widget — the current task list edits only `calibration_screen.dart`, which cannot resolve this on its own.

### 2. First mode emission after every connect will fire `playModeChange`
Task 6's listener has no first-emission guard. `device.modeChangedStream` (`lib/src/api/device.dart:67`) is a `receiveBroadcastStream` cache with no replay, but the native side emits the current mode promptly on subscription / mode entry, so each `Connect → Start` cycle will play the mode-change cue once before the user has touched anything. The roadmap doesn't explicitly forbid this, but combined with the calibration-only guard it produces an unprompted "you connected" beep that the user didn't trigger. Either accept this explicitly in the plan or guard with a "skip first emission" flag (simple `bool _seenInitialMode` in `_DeviceScreenState`, or check `prev != null` in the listener).

## Other Issues

### 3. Converting `_CalibrationCard` to `ConsumerStatefulWidget` is unnecessary and inconsistent with the codebase
Task 4 says "Convert `_CalibrationCard` from `ConsumerWidget` to `ConsumerStatefulWidget`." `ref.listen` works inside `ConsumerWidget.build(BuildContext, WidgetRef)` directly — the codebase already does this:
- `example/lib/screens/classifiers_screen.dart:78‑93` (`_PhysioCard extends ConsumerWidget` with `ref.listen` in `build`)
- `example/lib/screens/productivity_cardio_screen.dart:249‑257` (`_CardioCard` same pattern)

The conversion adds a `State` class with no state to hold and breaks the local symmetry of `_CalibrationCard / _IdleContent / _ActiveContent / _DoneContent / _ErrorContent / _NfbCard / _CalibrationDataCard` (all `ConsumerWidget`). Drop the conversion; just add the two `ref.listen` calls at the top of the existing `build` method.

### 4. Splitting `SoundService` and its provider into two files breaks project convention
Tasks 2 and 3 create `sound_service.dart` (class) and `sound_service_provider.dart` (provider). Every existing notifier-bearing provider in `example/lib/providers/` keeps the class and the provider in **one** file:
- `calibration_provider.dart` (`CalibrationNotifier` + `calibrationProvider`)
- `active_device_provider.dart` (`ActiveDeviceNotifier` + `activeDeviceProvider`)
- `calibration_timer_provider.dart` (`CalibrationTimerNotifier` + `calibrationTimerProvider`)

There's no Riverpod or analyzer reason to split. The plan also justifies the split by saying "single provider per file" is the convention, which contradicts `device_state_providers.dart` (three providers in one file — and the plan adds a fourth there). Recommendation: collapse Tasks 2 and 3 into one file `example/lib/providers/sound_service_provider.dart` containing both the class and the provider.

### 5. Single shared `AudioPlayer` cannot overlap cues
`SoundService` holds `final AudioPlayer _player = AudioPlayer();` and reuses it for all four sounds. `audioplayers` documents that calling `play()` on a busy player stops the previous playback and starts the new one. With the calibration guard in Task 6 the most likely overlap (mode-change while a stage starts) is suppressed, but `playStageStart` immediately followed by another `playStageStart` (not realistic with 4-stage calibration) or `playDone` immediately after `playStageStart` (possible — `CalibrationStageFinished` for stage4 leads quickly to `CalibrationCompleted`) will truncate the first cue. Acceptable for short cues; flag it explicitly as accepted, or use one `AudioPlayer` per cue (or `AudioPool`) if simultaneity matters.

### 6. Async `play()` futures are intentionally unawaited and uncaught
Task 2 says: "Do not catch errors; let them surface (the calling Riverpod listener won't await)." Unawaited futures that reject become unhandled async errors and surface in `FlutterError.onError` / `runZonedGuarded`, which is noisier than necessary in the example app. Recommend: fire-and-forget but attach a no-op `.catchError`, or wrap in `unawaited(...)` + try/catch with a `log(..., name: 'SoundService')` on failure (consistent with the `log(..., name: 'Neiry')` style used elsewhere).

### 7. iOS audio-session & Android background-playback behavior not addressed
`audioplayers` on iOS defaults to the `playback` audio category, which **stops other audio (music) when a sound plays** unless `AudioContext` is configured. For short cues that's usually fine, but worth one explicit decision in the plan: either set `AudioPlayer.global.setAudioContext(...)` once at startup with `.ambient` (so cues mix without ducking music), or document that defaults are accepted. Not a blocker; a known gotcha worth surfacing.

### 8. `ref.listen` previous-value semantics — minor correctness check
For `calibrationTimerProvider` (a non-nullable record `({int elapsed, CalibrationStage? stage})`), `prev` in the listener callback is typed as `T?` — first-emission `prev` is `null`. The plan's `next.stage != prev?.stage` works but a cleaner reading is `next.stage != prev?.stage` is `true` whenever `prev` is `null` and `next.stage` is non-null — i.e., it does fire on the very first stage transition (intended). Confirm this matches the desired behavior; per the milestone "covers both the initial transition into stage 1 and subsequent stage advances", this is correct.

## Positive Notes

- API surfaces are accurate: `device.modeChangedStream` returns `Stream<NeiryDeviceMode>` (`lib/src/api/device.dart:246‑249`), `NeiryDeviceMode` is exported from `package:neiry_kit/neiry_kit.dart`, `CalibrationStage` is the right enum, `IndividualNfbData` is the value type. No phantom imports.
- Asset path encoding is correct: `audioplayers`' `AssetSource('sounds/foo.wav')` resolves under the `assets/` prefix bundled by `flutter.assets: - assets/sounds/`.
- Provider placement is correct: `deviceModeProvider` in `device_state_providers.dart` is consistent with the existing `deviceConnectionStateProvider` pattern there.
- Stream lifecycle is handled correctly: `Stream.empty()` when no active device, automatic re-subscription on `activeDeviceProvider` change via `ref.watch`.
- Commit plan splits cleanly along reviewable boundaries (infrastructure first, wiring second).

## Required Changes Before Implementation

1. **(Critical, blocks correctness)** Resolve the abort-fires-error-and-done bug by extending the plan to modify `CalibrationNotifier.abort()` (or to add an aborting-flag check the listener consults). The widget-only listener cannot satisfy "do not play on abort".
2. **(Recommended)** Drop the unnecessary `ConsumerWidget → ConsumerStatefulWidget` conversion in Task 4; use `ref.listen` directly in the existing `build` method.
3. **(Recommended)** Collapse Tasks 2 and 3 into a single file matching existing notifier+provider co-location convention.
4. **(Optional)** Add a first-mode-emission guard to Task 6 to suppress the per-connect beep; or explicitly document the cue fires once on connect.
5. **(Optional)** Decide explicitly on AudioPlayer concurrency (single shared player vs. pool) and iOS audio session category, even if the answer is "defaults are fine".

