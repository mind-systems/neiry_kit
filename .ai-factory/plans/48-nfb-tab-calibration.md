# Plan: NFB tab + calibration

## Context

Implement the Calibration tab in the example app — full 4-stage and quick NFB calibration with a client-side timer, import/export of calibration data as JSON, an NFB classifier provider gated on device state, and a shared `nfbCalibrationProvider` that downstream tabs (Productivity, Cardio) will consume.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: State models and timer

- [x] **Task 1: CalibrationUiState sealed class**
  Files: `example/lib/providers/calibration_ui_state.dart`
  Create a sealed class `CalibrationUiState` with four subtypes:
  - `CalibrationIdle` — computed `instruction` getter returns `'Press Start to begin calibration'`.
  - `CalibrationStageActive(CalibrationStage stage, int elapsedSeconds)` — computed `stageLabel` getter returns `'Stage ${stage.code + 1} / 4'`; computed `instruction` getter uses a switch on `stage`: `stage1`/`stage3` = `'Close your eyes and relax'`, `stage2`/`stage4` = `'Open your eyes, look straight ahead'`.
  - `CalibrationDone(IndividualNfbData data)` — computed `isValid` getter delegates to `data.isValid`.
  - `CalibrationError(String message)`.
  Import `CalibrationStage` and `IndividualNfbData` from `neiry_kit`.

- [x] **Task 2: CalibrationTimerNotifier**
  Files: `example/lib/providers/calibration_timer_provider.dart`
  Create `CalibrationTimerNotifier extends StateNotifier<({int elapsed, CalibrationStage? stage})>` with initial state `(elapsed: 0, stage: null)`. Methods:
  - `startStage(CalibrationStage stage)` — cancels existing `_timer`, resets state to `(elapsed: 0, stage: stage)`, creates `Timer.periodic(1s)` that increments `elapsed`.
  - `stop()` — cancels timer, resets state to `(elapsed: 0, stage: null)`.
  - Override `dispose()` — cancels `_timer`, calls `super.dispose()`.
  Export as `calibrationTimerProvider = StateNotifierProvider<CalibrationTimerNotifier, ({int elapsed, CalibrationStage? stage})>(...)`.
  Follow the `ResistanceMapNotifier` pattern from `stream_providers.dart` for `StateNotifier` + `ref.onDispose` conventions — but here `StateNotifierProvider` manages its own `dispose()` lifecycle automatically.

### Phase 2: Core providers

- [x] **Task 3: CalibrationNotifier — full + quick calibration** (depends on Task 2)
  Files: `example/lib/providers/calibration_provider.dart`
  Create `CalibrationNotifier extends AsyncNotifier<IndividualNfbData?>`. Key details:

  **`build()`**: calls `NfbCalibrator.getCalibrationData()` to load any persisted calibration. Registers `ref.onDispose(() { _sub?.cancel(); _fullCompleter = null; })` for subscription cleanup (no overridable `dispose()` on `AsyncNotifier`).

  **`startFull()`**:
  1. `await WakelockPlus.enable()`.
  2. Set `state = const AsyncValue.loading()`.
  3. Create `_fullCompleter = Completer<IndividualNfbData>()`.
  4. Start timer for stage 1 immediately: `ref.read(calibrationTimerProvider.notifier).startStage(CalibrationStage.stage1)`.
  5. `_sub = NfbCalibrator.calibrateIndividual().listen(...)`.
  6. In `listen` callback, switch on event:
     - `CalibrationStageFinished(:final stage)` — guard `if (stage.code < 3)` then `timer.startStage(CalibrationStage.fromCode(stage.code + 1))`. Do NOT index into `CalibrationStage.values` — `fromCode` is the safe accessor.
     - `CalibrationCompleted(:final data)` — `timer.stop()`, complete `_fullCompleter` if not already completed.
  7. `onError:` — `timer.stop()`, complete `_fullCompleter` with error if not completed.
  8. Wrap the completer future in `AsyncValue.guard` with a `try/finally` that disables wakelock in `finally`:
     ```dart
     state = await AsyncValue.guard(() async {
       try {
         return await _fullCompleter!.future;
       } finally {
         await WakelockPlus.disable();
       }
     });
     ```
  9. After guard, conditionally write to shared provider: `if (state.hasValue && state.value != null) ref.read(nfbCalibrationProvider.notifier).state = state.value`.

  **`startQuick()`**:
  1. `await WakelockPlus.enable()`, set loading.
  2. `state = await AsyncValue.guard(() async { try { return await NfbCalibrator.calibrateIndividualQuick(); } finally { await WakelockPlus.disable(); } })`.
  3. Same conditional write to `nfbCalibrationProvider`.

  **`abort()`**:
  1. If `_fullCompleter != null && !_fullCompleter!.isCompleted`, complete it with `StateError('Calibration aborted')`.
  2. `_sub?.cancel(); _sub = null; _fullCompleter = null;`.
  3. `ref.read(calibrationTimerProvider.notifier).stop()`.
  4. `await WakelockPlus.disable()`.
  5. `state = AsyncValue.data(await NfbCalibrator.getCalibrationData())`.

  **`importFromFile()`**: use `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'])`. Read file, `jsonDecode`, `IndividualNfbData.fromMap`. Call `NfbCalibrator.importCalibrationData(data)`. Set `state = AsyncValue.data(data)`. Write to `nfbCalibrationProvider`.

  **`exportToFile()`**: guard `state.value != null`. Get `getApplicationDocumentsDirectory()`, write JSON via `data.toMap()` → `jsonEncode`. Show path in snackbar (or just return the File — UI handles the message).

  Export as `calibrationProvider = AsyncNotifierProvider<CalibrationNotifier, IndividualNfbData?>(...)`.

- [x] **Task 4: Shared nfbCalibrationProvider**
  Files: `example/lib/providers/nfb_calibration_provider.dart`
  Create `nfbCalibrationProvider = StateProvider<IndividualNfbData?>((ref) => null)`. This is the cross-tab shared state that Calibration tab writes to and Productivity/Cardio tab reads from. Simple `StateProvider` — no notifier class needed.

- [x] **Task 5: NfbClassifierNotifier** (depends on Task 4)
  Files: `example/lib/providers/nfb_classifier_provider.dart`
  Create `NfbClassifierNotifier extends Notifier<NfbClassifier?>`. In `build()`:
  - Watch `activeDeviceProvider` and `deviceIsStartedProvider`.
  - If device is null or not started, return `null`.
  - Read `nfbCalibrationProvider` for optional calibration data.
  - Create `NfbClassifier(device, calibration: calibrationData)`.
  - Register `ref.onDispose(() { final c = state; c?.dispose(); })` — capture the local classifier instance, do NOT read `state` inside the dispose callback (state may have changed by the time dispose fires).
  - Return the classifier.
  Export as `nfbClassifierProvider = NotifierProvider<NfbClassifierNotifier, NfbClassifier?>(...)`.

  Also create `nfbStateProvider = StreamProvider<NfbUserState>((ref) { ... })`:
  - Watch `nfbClassifierProvider`. If null, return `Stream.empty()`.
  - Return `classifier.stateStream`.

### Phase 3: Calibration screen UI

- [x] **Task 6: CalibrationScreen implementation** (depends on Tasks 1, 3, 4, 5)
  Files: `example/lib/screens/calibration_screen.dart`
  Replace the stub with a `ConsumerWidget`. Follow the card-based layout pattern from `StreamsScreen`. Structure:

  **Calibration section** (top):
  - Derive `CalibrationUiState` locally from `calibrationProvider` and `calibrationTimerProvider`:
    - `calibrationProvider` is loading → map timer state to `CalibrationStageActive(timer.stage, timer.elapsed)` if timer has a stage, else show a generic loading indicator.
    - `calibrationProvider` has error → `CalibrationError(error.toString())`.
    - `calibrationProvider` has data with non-null value → `CalibrationDone(data)`.
    - `calibrationProvider` has data with null value → `CalibrationIdle()`.
  - Render based on sealed state:
    - `CalibrationIdle`: instruction text + "Start Full" and "Start Quick" buttons + "Import" button.
    - `CalibrationStageActive`: stage label, instruction text, elapsed timer `"${elapsed}s"`, "Abort" button.
    - `CalibrationDone`: "Calibration complete" + validity status + "Export" button + "Recalibrate" button.
    - `CalibrationError`: error message + "Retry" button.
  - Button handlers call `ref.read(calibrationProvider.notifier).startFull()` etc.
  - Export button calls `exportToFile()`, shows snackbar with file path on success.
  - Import success updates UI reactively via `calibrationProvider` state change.

  **NFB classifier section** (below calibration):
  - `_NfbCard` as a private `ConsumerWidget`.
  - Watch `nfbClassifierProvider`. If null, show "Waiting for device..." text (same pattern as streams tab loading state).
  - If classifier exists, watch `nfbStateProvider.when(...)`:
    - `data:` — show `NfbUserState` fields (delta, theta, alpha, smr, beta) each with label and value formatted to 3 decimal places, or "—" when null.
    - `loading:` — "Waiting for NFB data...".
    - `error:` — error text.

- [x] **Task 7: CalibrationFileManager helper** (depends on Task 3)
  Files: `example/lib/providers/calibration_file_manager.dart`
  Extract file I/O into a static helper class `CalibrationFileManager` with two methods:
  - `static Future<File?> exportToFile(IndividualNfbData data)` — writes `jsonEncode(data.toMap())` to app documents dir with timestamp filename `calibration_<millis>.json`.
  - `static Future<IndividualNfbData?> importFromFile()` — opens `FilePicker` for `.json`, reads file, `jsonDecode`, `IndividualNfbData.fromMap`. Returns null if user cancels.
  `CalibrationNotifier` (Task 3) delegates to this class for its `importFromFile()` and `exportToFile()` methods.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add CalibrationUiState sealed class and CalibrationTimerNotifier"
- **Commit 2** (after tasks 3-5): "Add calibration, shared NFB, and classifier providers"
- **Commit 3** (after tasks 6-7): "Implement CalibrationScreen UI with NFB card and file I/O helper"
