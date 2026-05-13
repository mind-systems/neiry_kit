# Plan Review: Sound cues for calibration stage transitions and device mode changes (v2)

**Plan:** `.ai-factory/plans/62-sound-cues-for-calibration-stage-transitions-and-device-mode-changes.md`
**Risk Level:** 🟢 Low

## Summary

V2 cleanly addresses every issue raised in `plan-review-1.md`:

- Abort no longer fires error+done cues — Task 3 adds an `isAborting` getter on `CalibrationNotifier` that Task 4's listener consults.
- Mode-change first emission is guarded via `prev is! AsyncData` in Task 6.
- `_CalibrationCard` stays a `ConsumerWidget` (matches `_PhysioCard` / `_CardioCard`).
- `SoundService` and its provider are co-located in one file (matches `calibration_provider.dart`, `active_device_provider.dart`, …).
- Shared `AudioPlayer` and unawaited futures are now explicit design decisions; `play*` methods attach `.catchError` + `log` so failed plays don't leak as unhandled async errors.
- iOS audio-session decision is documented (defaults accepted — fine for the example app).

File paths, provider locations, exported types (`NeiryDeviceMode`, `CalibrationStage`, `IndividualNfbData`), stream surfaces (`device.modeChangedStream` at `lib/src/api/device.dart:246`), and asset paths (`AssetSource('sounds/foo.wav')` resolves under `assets/sounds/`) all check out against the actual codebase.

## Context Gates

- **ARCHITECTURE.md** — present. Plan is example-app-only; no plugin/example boundary violation. ✅
- **RULES.md** — absent. No project-rules gate to run.
- **ROADMAP.md** — present (milestone "Sound cues" near line 83). Plan tracks the milestone description verbatim. ✅
- **`.ai-factory/skill-context/aif-review/SKILL.md`** — absent. No project overrides apply.

## Critical Issues

None.

## Other Issues

### 1. Task 3's microtask clear of `_aborted` rests on Riverpod listeners firing synchronously — verify or harden

The plan's correctness argument is:

> Riverpod's `ref.listen` callback runs synchronously on the state assignment, so the listener will observe `isAborting == true` and skip cues […]. After the final `state = AsyncValue.data(...)` assignment, schedule a microtask to clear it.

Walking the abort flow against `calibration_provider.dart:96‑107`:

1. `_aborted = true`; `_fullCompleter.completeError(...)` (queues microtask M1 to resume `startFull`).
2. abort runs `await WakelockPlus.disable()` → suspends.
3. M1: `startFull` resumes from `await _fullCompleter!.future` → throw → `finally { await WakelockPlus.disable(); }` → suspends.
4. abort's wakelock future resolves first (issued first); abort resumes and calls `await NfbCalibrator.getCalibrationData()` — this is a `MethodChannel` round-trip (`lib/src/api/nfb_calibrator.dart:272`), so it suspends with a meaningful yield window.
5. During that yield, `startFull`'s wakelock future resolves, `AsyncValue.guard` catches the error, and `state = AsyncError(...)` is assigned — while `_aborted == true`.
6. `NfbCalibrator.getCalibrationData()` returns; abort runs `state = AsyncValue.data(...)` — still while `_aborted == true`.
7. `Future.microtask(() => _aborted = false)` queued; abort returns.

So in the **expected** ordering (which is robust thanks to the channel round-trip in step 4), both state writes happen while `_aborted` is true, and the listener skips both. This works.

However, **the argument is sensitive to two assumptions**:

- **(a) `ref.listen` fires synchronously on state assignment in Riverpod 3.x.** The project pins `riverpod: ^3.2.0` (`example/pubspec.yaml:32`). In Riverpod 3 the default scheduler is generally synchronous for notifier state writes, but this isn't formally guaranteed in user-facing docs. If a future Riverpod update batches listener flushes onto a microtask, then in `abort()`:
  - `state = AsyncValue.data(...)` queues a listener-notify microtask (LN).
  - `Future.microtask(() => _aborted = false)` queues a clear microtask (C).
  - Order in the microtask queue: LN, C. Drain runs LN with `_aborted = true` (skipped), then C clears.
  - But the *concurrent* `state = AsyncError` from `startFull` could queue *its* listener-notify microtask either before LN (fine) or after C (bad — fires `playError`).
  - The ordering depends on how Riverpod batches/schedules; with multiple suspension points between the two state writes (steps 4–6), they probably don't coalesce.

- **(b) The two `await WakelockPlus.disable()` calls and `await NfbCalibrator.getCalibrationData()` between them keep the timeline above intact.** Today this is true. If anyone removes the `await getCalibrationData()` (e.g. caches it client-side) the yield window vanishes and abort can finish its full sequence before `startFull` ever assigns `state = AsyncError` — at which point the microtask `_aborted = false` may run before the listener sees the error transition.

**Recommendation (cheap, defensive, no scope creep):** clear `_aborted` deterministically rather than via a stray microtask. Two equally simple options, pick one and call it out in the plan:

- **(i)** Don't clear `_aborted` in `abort()` at all. It is already reset at the top of `startFull` (line 35), and the same reset can be added to the top of `startQuick()` (one line) and `importFromFile()` (one line) for symmetry. Trade-off: between an abort and the next user action, `isAborting` reports `true`, which would also suppress a hypothetical `playError` from `importFromFile` failing right after an abort. Acceptable — that error path is rare and not part of the milestone.
- **(ii)** Have `startFull` clear `_aborted` *after* it writes the post-guard state, e.g. add `_aborted = false;` immediately before the `return` on line 73 and after `_writeToSharedProvider()`. That keeps the flag alive for exactly as long as `startFull`'s flow is still touching state, removing the cross-task race entirely. No microtask trick required.

Either change is one line and removes a fragile assumption.

### 2. Retry path (`ref.invalidate(calibrationProvider)`) can spuriously fire `playDone`

`_ErrorContent.onPressed` calls `ref.invalidate(calibrationProvider)` (`calibration_screen.dart:236`). On invalidate, the notifier is disposed and rebuilt; `build()` returns `AsyncData(NfbCalibrator.getCalibrationData())`. If a previous successful calibration exists on the native side (common — that's exactly why the user is on the Calibration screen), the rebuilt state transitions from the previous `AsyncError` (or possibly an intermediate `AsyncLoading` during async build) to `AsyncData(<non-null>)`. The Task 4 listener edge `!prev.hasValue && next.hasValue && next.value != null` then fires `playDone` on a button labelled "Retry" — which is not a "done" event.

The `_aborted` flag does not cover this (retry is not an abort).

**Recommendation:** acknowledge this case explicitly in Task 4's notes and either:
- (i) accept it ("retry after error replays the done cue if prior calibration data exists"), or
- (ii) gate `playDone` on a "we just left loading" edge — currently the listener already requires `!prev.hasValue`, but invalidate transitions go `AsyncError → AsyncLoading → AsyncData`, which still satisfies `!prev.hasValue` at the loading→data step. A simple narrowing is `prev is AsyncLoading` (or `prev.isLoading`) instead of `!prev.hasValue`. That restricts `playDone` to the "calibration just finished" transition and excludes the invalidate-rebuild path.

Not a blocker for the milestone, but worth one line in Task 4 either way (the milestone says "play `done.wav` after calibration completes" — playing it on Retry violates that).

### 3. Stage listener relies on record-equality semantics — confirm

`calibrationTimerProvider` exposes `CalibrationTimerState = ({int elapsed, CalibrationStage? stage})`. The notifier reassigns `state` every tick (`calibration_timer_provider.dart:29`), so `ref.listen` fires once per second during a stage. Task 4's guard `next.stage != prev?.stage` short-circuits correctly for tick updates (same stage), but it's worth noting in the plan: this listener fires every second; only the guard prevents a beep per tick. Currently the guard handles this correctly — flagging only so the implementer doesn't "simplify" it away.

### 4. `playStageStart` cue when `CalibrationStageFinished` for stage 4 arrives

Look at `startFull` (`calibration_provider.dart:46-48`): on `CalibrationStageFinished(stage)` with `stage.code < 3`, it advances the timer; for stage 4 it does NOT advance (correct — there's no stage 5). The done cue then fires on `CalibrationCompleted` → state = AsyncData. That's the intended sequence: stage1 cue → stage2 cue → stage3 cue → stage4 cue → done cue. ✅ — included only to note that the listener choice correctly produces five cues, not four.

## Positive Notes

- **API surfaces verified directly against source:**
  - `device.modeChangedStream` returns `Stream<NeiryDeviceMode>` (`lib/src/api/device.dart:246-249`).
  - `NeiryDeviceMode` is exported from the plugin barrel (`package:neiry_kit/neiry_kit.dart`) and already imported in `device_state_providers.dart` (no new imports needed for Task 5).
  - Asset directory entry `assets/sounds/` correctly bundles the four WAVs; `AssetSource('sounds/foo.wav')` resolves under that prefix.
- **Pattern compliance:** Task 4 explicitly preserves the `ConsumerWidget` pattern of sibling cards in `calibration_screen.dart`. Co-located service+provider in Task 2 mirrors the project convention used by every notifier in `example/lib/providers/`.
- **First-emission guards:** Task 6 has two distinct guards (`prev == null` for build-time, `prev is! AsyncData` for post-resubscribe). This correctly suppresses the connect-time mode beep while letting subsequent `AsyncData → AsyncData` transitions through.
- **Stream lifecycle:** Task 5's `StreamProvider` returns `Stream.empty()` when no active device — matches the pattern used by `deviceConnectionStateProvider` in the same file.
- **Error swallowing:** the `.catchError` pattern in Task 2 is the right shape for fire-and-forget audio calls and is consistent with the `log(..., name: 'Neiry')` style already used across the example app.
- **Commit plan** splits cleanly along reviewable boundaries (infra → calibration wiring → device mode wiring).

## Recommended Changes Before Implementation

1. **(Recommended, single-line fix)** Harden Task 3 against the implicit timing assumption: drop the `Future.microtask` clear and instead reset `_aborted = false` at the end of `startFull` (after `_writeToSharedProvider()`/early-return), or at the top of `startQuick`/`importFromFile`. Document the choice in Task 3.
2. **(Recommended, one-line listener tweak)** In Task 4's `playDone` edge, replace `!prev.hasValue && next.hasValue && next.value != null` with a narrower `prev is AsyncLoading && next.hasValue && next.value != null` (or equivalent `prev.isLoading` form) so a Retry-driven `ref.invalidate` doesn't replay the done cue when prior calibration data exists. Or explicitly accept that behaviour in the plan notes.
3. **(Optional)** Add one sentence to Task 4 noting that the stage listener fires per second and the `next.stage != prev?.stage` guard is load-bearing — so the implementer doesn't restructure it.

None of these are blockers; the plan as written produces a working implementation under expected conditions. The changes above eliminate two narrow but real edge cases (cross-task race on abort flag, Retry replaying done cue).

PLAN_REVIEW_PASS
