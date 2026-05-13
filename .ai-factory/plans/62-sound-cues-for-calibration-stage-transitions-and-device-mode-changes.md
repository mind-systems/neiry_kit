# Plan: Sound cues for calibration stage transitions and device mode changes

## Context
Add audio feedback to the example app so calibration stage advances, calibration completion/errors, and device mode changes (PPG, resistance) all play short cues. WAV assets already exist in `example/assets/sounds/` (`stage.wav`, `done.wav`, `error.wav`, `mode.wav`); this milestone wires them up via a Riverpod-provided `SoundService` built on `audioplayers`.

### Design decisions (resolved up front)
- **AudioPlayer concurrency:** single shared `AudioPlayer`. Cues are short (<1s); a later `play()` interrupting an earlier one is acceptable. Documented so it isn't re-litigated during implementation.
- **iOS audio session:** keep `audioplayers` defaults. No explicit `AudioContext` configuration; cues will use the default `playback` category. This is the example app, not the production app — surfacing the trade-off is enough.
- **Unawaited play futures:** the Riverpod listeners deliberately don't `await` the play call. Attach `.catchError` and `log(..., name: 'SoundService')` so a failed `play()` doesn't leak as an unhandled async error.
- **Abort flow:** the existing `CalibrationNotifier.abort()` produces a `loading → error → data` state sequence (via `_fullCompleter.completeError` then `state = AsyncValue.data(...)`). A widget-only listener cannot tell that sequence apart from a real error followed by a recovery. Fix at the notifier level by exposing an `isAborting` flag the listener consults; see Task 4.
- **Mode-change first emission:** suppress the cue on the first mode emission after a stream subscription begins (i.e. right after connect) so the user doesn't hear a beep they didn't ask for. Implemented via a `prev == null` guard in the listener.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dependency & asset wiring

- [x] **Task 1: Add audioplayers dependency and register sound assets**
  Files: `example/pubspec.yaml`
  Under `dependencies:` add `audioplayers: ^6.1.0` (place it alongside the other third-party deps such as `flutter_riverpod`, `go_router`). Under the `flutter:` section, add an `assets:` list (the current file has only a commented-out example) containing `assets/sounds/` so that `stage.wav`, `done.wav`, `error.wav`, `mode.wav` are bundled. Use a trailing-slash directory entry rather than per-file enumeration.

### Phase 2: Sound service

- [x] **Task 2: Create `SoundService` and its Riverpod provider in one file** (depends on Task 1)
  Files: `example/lib/providers/sound_service_provider.dart` (new)
  Co-locate the class and the provider in a single file, matching the existing notifier+provider convention in `example/lib/providers/` (`calibration_provider.dart`, `active_device_provider.dart`, `calibration_timer_provider.dart`).
  - Declare a plain Dart class `SoundService` (not Riverpod-aware) holding one shared `AudioPlayer`:
    ```dart
    final AudioPlayer _player = AudioPlayer();
    ```
  - Expose four methods that play the corresponding asset via `_player.play(AssetSource('sounds/<name>.wav'))`:
    - `Future<void> playStageStart()` → `stage.wav`
    - `Future<void> playDone()` → `done.wav`
    - `Future<void> playError()` → `error.wav`
    - `Future<void> playModeChange()` → `mode.wav`
  - Add `Future<void> dispose()` that calls `_player.dispose()`.
  - At the bottom of the same file, add the provider:
    ```dart
    final soundServiceProvider = Provider<SoundService>((ref) {
      final service = SoundService();
      ref.onDispose(service.dispose);
      return service;
    });
    ```
  - Imports: `package:audioplayers/audioplayers.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, `dart:developer` (for `log`).

  Callers will invoke methods fire-and-forget — they're not responsible for catching failures. Each `play*` method must therefore swallow its own errors via `.catchError`, logging at minimal verbosity, e.g.:
  ```dart
  Future<void> playStageStart() => _player
      .play(AssetSource('sounds/stage.wav'))
      .catchError((Object e, StackTrace st) {
        log('playStageStart failed: $e', name: 'SoundService', error: e, stackTrace: st);
      });
  ```
  Apply the same pattern to the other three methods.

### Phase 3: Calibration screen wiring

- [x] **Task 3: Expose abort signal on `CalibrationNotifier`** (depends on Task 2)
  Files: `example/lib/providers/calibration_provider.dart`
  The current `abort()` flow drives state through `loading → error → data`, so a widget listener would fire both `playError()` and (if previous calibration data exists) `playDone()` on a single abort — neither of which is acceptable per the milestone.

  Reuse the existing private `_aborted` flag and expose it through a public getter so the listener can suppress cues during the entire abort transition:
  1. Add `bool get isAborting => _aborted;` on the notifier.
  2. In `abort()`, keep `_aborted = true` set across the full sequence (it is already; do not clear it inside `abort()`). After the final `state = AsyncValue.data(...)` assignment, schedule a microtask to clear it: `Future.microtask(() => _aborted = false);`. Riverpod's `ref.listen` callback runs synchronously on the state assignment, so the listener will observe `isAborting == true` and skip cues, and any future calibration run will see a clean flag (and `startFull` resets it at the top either way).
  3. Verify nothing else in the notifier reads `_aborted` after the state assignment in `abort()` — it does not (only `startFull` checks it on line 73, but that path returns earlier when abort fires).

  No changes to public method signatures; this is purely an additive getter plus a microtask reset.

- [x] **Task 4: Play stage/done/error cues from `_CalibrationCard`** (depends on Task 3)
  Files: `example/lib/screens/calibration_screen.dart`
  Keep `_CalibrationCard` as `ConsumerWidget` — the codebase already calls `ref.listen` inside `ConsumerWidget.build` (e.g. `_PhysioCard` in `classifiers_screen.dart`, `_CardioCard` in `productivity_cardio_screen.dart`). Do **not** convert it to `ConsumerStatefulWidget`; that would break the local symmetry with the sibling `_NfbCard` / `_CalibrationDataCard` widgets.

  At the very top of the existing `build(BuildContext, WidgetRef)` (before the `ref.watch` calls), add two listeners. Both must short-circuit when an abort is in flight by reading `ref.read(calibrationProvider.notifier).isAborting`:

  ```dart
  ref.listen(calibrationTimerProvider, (prev, next) {
    if (next.stage != null && next.stage != prev?.stage) {
      ref.read(soundServiceProvider).playStageStart();
    }
  });

  ref.listen<AsyncValue<IndividualNfbData?>>(calibrationProvider, (prev, next) {
    if (prev == null) return; // ignore the initial build emission
    final notifier = ref.read(calibrationProvider.notifier);
    if (notifier.isAborting) return; // abort()'s loading→error→data transitions
    final sound = ref.read(soundServiceProvider);
    if (!prev.hasValue && next.hasValue && next.value != null) {
      sound.playDone();
    } else if (!prev.hasError && next.hasError) {
      sound.playError();
    }
  });
  ```

  Notes:
  - The stage listener fires on the initial `null → stage1` transition (intentional — covers the first stage start).
  - The done/error listener uses the boolean edge `!prev.hasError → next.hasError` and `!prev.hasValue → next.hasValue && value != null` so it can't fire on idle (the post-build state with `value == null` is `hasValue == true && value == null`, so the value-null check is required).
  - Add imports: `../providers/sound_service_provider.dart` and (if not already present) keep the existing `../providers/calibration_provider.dart` import.

### Phase 4: Device mode-change wiring

- [x] **Task 5: Add `deviceModeProvider` stream** (depends on Task 2)
  Files: `example/lib/providers/device_state_providers.dart`
  Add a `StreamProvider<NeiryDeviceMode>` next to the existing `deviceConnectionStateProvider`, forwarding `device.modeChangedStream` for the currently active device:
  ```dart
  final deviceModeProvider = StreamProvider<NeiryDeviceMode>((ref) {
    final device = ref.watch(activeDeviceProvider);
    if (device == null) return const Stream.empty();
    return device.modeChangedStream;
  });
  ```
  `NeiryDeviceMode` is already exported from `package:neiry_kit/neiry_kit.dart` and imported in this file; no new imports required.

- [x] **Task 6: Play mode-change cue from `DeviceScreen` with guards** (depends on Tasks 4 and 5)
  Files: `example/lib/screens/device_screen.dart`
  Inside `_DeviceScreenState.build`, immediately after the existing `ref.watch` calls, register the listener:
  ```dart
  ref.listen<AsyncValue<NeiryDeviceMode>>(deviceModeProvider, (prev, next) {
    if (prev == null) return; // first build — no transition to announce
    if (ref.read(calibrationProvider).isLoading) return; // calibration owns audio
    next.whenData((mode) {
      // Suppress the first emission after (re)subscription so a fresh connect
      // doesn't beep before the user has done anything.
      if (prev is! AsyncData<NeiryDeviceMode>) return;
      ref.read(soundServiceProvider).playModeChange();
    });
  });
  ```
  Two guards:
  - `prev == null` skips the build-time emission of the listener itself.
  - `prev is! AsyncData` skips the first real value emitted by a fresh subscription (i.e. right after connect, when the native side emits the current mode). Subsequent mode transitions (`AsyncData → AsyncData`) pass through.

  Add imports: `../providers/sound_service_provider.dart` and `../providers/calibration_provider.dart`.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add SoundService wired through Riverpod with bundled WAV assets"
- **Commit 2** (after tasks 3-4): "Trigger stage/done/error cues on calibration transitions"
- **Commit 3** (after tasks 5-6): "Trigger cue on device mode change with calibration and first-emission guards"
