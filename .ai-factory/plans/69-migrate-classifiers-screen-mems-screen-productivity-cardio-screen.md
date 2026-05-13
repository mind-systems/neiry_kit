# Plan: Migrate classifiers_screen, mems_screen, productivity_cardio_screen

## Context

Finish the example-app refactor by routing the last three screens through the new `NeiryService` + `classifier_stream_providers.dart` + action-notifier surface. These screens currently fail to compile because they still import the deleted `*_classifier_provider.dart` files and reference symbols that no longer exist: `emotionsClassifierProvider`, `physioClassifierProvider`, `memsClassifierProvider`, `cardioClassifierProvider`, `productivityClassifierProvider`, `physioCalibratedProvider`, `cardioCalibratedProvider`, `useMemsCalibrationToggleProvider`, `useCalibrationToggleProvider`.

Key facts gathered during exploration:

- All six `*_classifier_provider.dart` files are deleted on disk (milestone 90). Replacements: data is in `classifier_stream_providers.dart`; commands are in `physio_actions_provider.dart` / `productivity_actions_provider.dart`.
- `NeiryService` eagerly creates all six classifiers on `connect()` and exposes them via stream getters (`physioStream`, `emotionsStream`, `cardioStream`, `cardioPpgStream`, `memsStream`, `nfbStream`, `productivityIndexesStream`, `productivityMetricsStream`) plus `physioCalibrationProgressStream` / `productivityCalibrationProgressStream`. It does **not** currently expose the calibration-completion event streams (`PhysioClassifier.calibrated`, `CardioClassifier.calibratedStream`) — those must be added before `physioCalibratedProvider` / `cardioCalibratedProvider` can be re-created.
- `useCalibrationToggleProvider` (productivity+cardio) and `useMemsCalibrationToggleProvider` (mems) used to live inside the deleted classifier provider files. Per milestone 88 ("NeiryService — device layer singleton") calibration data is now a connect-time decision, not a runtime toggle — these two `StateProvider<bool>`s must be re-created as pure user-preference flags read by the connect flow (read sites are out of scope here; this milestone only re-creates the providers and updates UI semantics).
- `physioActionsProvider.notifier` exposes `startBaselineCalibration()` and `importBaselines(...)`; `productivityActionsProvider.notifier` exposes `startBaselineCalibration()` and `resetAccumulatedFatigue()`. Both are `NotifierProvider<…, void>` — no `.notifier` rebuild concerns.
- `classifiers_screen.dart` also currently imports `physio_baselines_file_manager.dart` for the Export Baselines button via `physioBaselinesProvider`. That provider already lives in `classifier_stream_providers.dart` and stays — no changes to the export flow.
- All preserved `log(..., name: 'Neiry')` calls from milestone 81 must be kept verbatim.

## Settings
- Testing: no
- Logging: minimal (preserve all existing `log(..., name: 'Neiry')` calls)
- Docs: no

## Tasks

### Phase 1: Expose calibration-completion streams

- [x] **Task 1: Add `physioCalibratedStream` and `cardioCalibratedStream` to `NeiryService`**
  Files: `example/lib/services/neiry_service.dart`
  - Add two private broadcast controllers next to the existing ones:
    - `final _physioCalibratedController = StreamController<PhysiologicalStatesBaselines>.broadcast();`
    - `final _cardioCalibratedController = StreamController<void>.broadcast();`
  - Inside `connect()`, in the same fan-in `_activeSubscriptions.addAll([...])` block where `_physio!.calibrationProgress` and `_productivity!.calibrationProgress` are wired, append two more `listen` entries:
    - `_physio!.calibrated.listen(_physioCalibratedController.add, onError: _physioCalibratedController.addError),`
    - `_cardio!.calibratedStream.listen((_) => _cardioCalibratedController.add(null), onError: _cardioCalibratedController.addError),`
  - In `dispose()`, after closing the two progress controllers, append `await _physioCalibratedController.close();` and `await _cardioCalibratedController.close();` (do not close in `disconnect()` — controllers must stay open across connect cycles, matching the existing pattern).
  - Add two public stream getters at the bottom of the data-streams section:
    - `Stream<PhysiologicalStatesBaselines> get physioCalibratedStream => _physioCalibratedController.stream;`
    - `Stream<void> get cardioCalibratedStream => _cardioCalibratedController.stream;`
  - Do not modify any existing field or method beyond these additions.

- [x] **Task 2: Re-create `physioCalibratedProvider` and `cardioCalibratedProvider`** (depends on Task 1)
  Files: `example/lib/providers/classifier_stream_providers.dart`
  - Add two new `StreamProvider`s next to the existing classifier stream providers, sourced from `NeiryService`:
    - `final physioCalibratedProvider = StreamProvider<PhysiologicalStatesBaselines>((ref) => ref.watch(neiryServiceProvider).physioCalibratedStream);`
    - `final cardioCalibratedProvider = StreamProvider<void>((ref) => ref.watch(neiryServiceProvider).cardioCalibratedStream);`
  - Place them after `productivityCalibrationProgressProvider` and before `physioBaselinesProvider` so related providers stay grouped.
  - Add doc comments mirroring the style of neighbouring providers (one-line `///` description).

### Phase 2: Re-create user-preference toggle providers

- [x] **Task 3: Add `useMemsCalibrationToggleProvider` and `useCalibrationToggleProvider`** (depends on Task 2)
  Files: `example/lib/providers/nfb_calibration_provider.dart`
  - Both providers are pure user-preference flags read at connect-time by whichever future code decides which `IndividualNfbData?` to pass to `NeiryService.connect(...)`. They have no device dependency and own no side effects.
  - Add to `nfb_calibration_provider.dart` (already a `legacy.dart`-importing file, so `StateProvider` is in scope):
    ```dart
    /// User preference: pass [nfbCalibrationProvider] as `nfbData` to
    /// [NeiryService.connect] for the MEMS classifier on the next connect.
    /// Read by the connect flow; flipping it while connected has no immediate
    /// effect — the new value takes effect on the next disconnect→connect cycle.
    final useMemsCalibrationToggleProvider = StateProvider<bool>((ref) => false);

    /// User preference: pass [nfbCalibrationProvider] as `nfbData` to
    /// [NeiryService.connect] for the Productivity and Cardio classifiers on the
    /// next connect. Same semantics as [useMemsCalibrationToggleProvider].
    final useCalibrationToggleProvider = StateProvider<bool>((ref) => false);
    ```
  - Do not modify the existing `nfbCalibrationProvider`.

### Phase 3: Migrate the three screens

- [x] **Task 4: Migrate `classifiers_screen.dart` to `physioActionsProvider` + stream-based gating** (depends on Task 3)
  Files: `example/lib/screens/classifiers_screen.dart`
  - Imports — remove:
    - `'../providers/emotions_classifier_provider.dart';`
    - `'../providers/physio_classifier_provider.dart';`
  - Imports — add:
    - `'../providers/classifier_stream_providers.dart';`
    - `'../providers/physio_actions_provider.dart';`
  - Keep `'../providers/physio_baselines_file_manager.dart';` unchanged (it owns the file IO helpers, not providers).
  - In `_EmotionsCard.build`:
    - Replace `final classifier = ref.watch(emotionsClassifierProvider);` with `final emotionsAsync = ref.watch(emotionsStateProvider);`.
    - Replace `if (classifier == null) const Text('Waiting for device...') else emotionsAsync.when(...)` with a single `emotionsAsync.when(loading: () => const Text('Waiting for device...'), error: (e, _) => Text('Error: $e'), data: (state) => Column(...))` — the `loading` branch now doubles as the "no device" message (Riverpod treats a `StreamProvider` watching a stream that has not yet emitted as loading).
    - Keep the existing `_MetricRow` children inside the `data:` branch unchanged.
  - In `_PhysioCard.build`:
    - Replace `final classifier = ref.watch(physioClassifierProvider);` with `final physioAsync = ref.watch(physioStateProvider);` and the existing `final baselines = ref.watch(physioBaselinesProvider);` stays.
    - Drop the `if (classifier == null) ... else ...[ ... ]` structural split. Restructure to always render the card body, with the per-state placeholders moved into `physioAsync.when(...)` exactly as in the Emotions card (loading → "Waiting for device...", data → metrics + signal quality + timestamp).
    - The calibration progress bar (`ref.watch(physioCalibrationProgressProvider).whenOrNull(...)`) and the three action buttons (`Start Baseline Calibration`, `Import Baselines`, `Export Baselines`) move out from inside the deleted `else ...[ ... ]` block to live alongside the `physioAsync.when(...)` widget — they are always visible (their underlying providers are themselves stream-aware and will show their own loading state when no device is connected).
    - Replace `ref.read(physioClassifierProvider.notifier).startBaselineCalibration()` with `ref.read(physioActionsProvider.notifier).startBaselineCalibration()`.
    - Replace `ref.read(physioClassifierProvider.notifier).importBaselines(result)` with `ref.read(physioActionsProvider.notifier).importBaselines(result)`.
    - Keep all four `log('Physio: …', name: 'Neiry')` calls byte-identical.
    - Keep `ref.listen(physioCalibratedProvider, (_, next) { if (next.hasValue) ... showSnackBar('Baselines calibrated') })` unchanged — `physioCalibratedProvider` now resolves via Task 2.

- [x] **Task 5: Migrate `mems_screen.dart` — always-on data view + preference-only toggle** (depends on Task 4)
  Files: `example/lib/screens/mems_screen.dart`
  - Imports — remove: `'../providers/mems_classifier_provider.dart';`
  - Imports — add: `'../providers/classifier_stream_providers.dart';`
  - Keep `'../providers/device_state_providers.dart';` and `'../providers/nfb_calibration_provider.dart';` — `useMemsCalibrationToggleProvider` is re-exported from `nfb_calibration_provider.dart` (Task 3), and `deviceUiStateProvider` is no longer needed (see below) so consider removing the `device_state_providers.dart` import once the `uiState` reference is gone.
  - In `MemsScreen.build`:
    - Delete `final classifier = ref.watch(memsClassifierProvider);`.
    - Delete `final uiState = ref.watch(deviceUiStateProvider);` and `final canEditToggle = uiState == DeviceUiState.idle;` — the toggle is now always editable as long as `nfbData != null`.
    - The `SwitchListTile` subtitle simplifies to:
      - When `nfbData == null` → `'Run calibration first to enable'` (unchanged).
      - When `nfbData != null` → `'Takes effect on next connect'` (replaces both the previous "Disconnect to change this setting" and the "Using individual NFB calibration" branches).
    - `onChanged: nfbData == null ? null : (val) { log('MEMS: Use NFB Calibration toggled: $val', name: 'Neiry'); ref.read(useMemsCalibrationToggleProvider.notifier).state = val; }` — preserve the `log()` call exactly.
    - `value: useCalibration && nfbData != null` — unchanged.
    - Replace the body's `if (classifier == null) const Text('Waiting for device...') else ref.watch(memsProvider).when(...)` with a direct `ref.watch(memsProvider).when(loading: () => const Text('Waiting for device...'), error: (e, _) => Text('Error: $e'), data: (samples) { if (samples.isEmpty) return const Text('Waiting for MEMS data...'); … })`. The existing `samples.last` handling and the two cards (Accelerometer, Gyroscope) stay byte-identical.

- [x] **Task 6: Migrate `productivity_cardio_screen.dart` — actions notifier + stream-based gating** (depends on Task 5)
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  - Imports — remove:
    - `'../providers/cardio_classifier_provider.dart';`
    - `'../providers/productivity_classifier_provider.dart';`
  - Imports — add:
    - `'../providers/classifier_stream_providers.dart';`
    - `'../providers/productivity_actions_provider.dart';`
  - Keep `'../providers/nfb_calibration_provider.dart';` — re-exports both `nfbCalibrationProvider` and (after Task 3) `useCalibrationToggleProvider`. Remove `'../providers/device_state_providers.dart';` once the `uiState`/`canEditToggle` references are gone (see below).
  - In `ProductivityCardioScreen.build`:
    - Delete `final uiState = ref.watch(deviceUiStateProvider);` and `final canEditToggle = uiState == DeviceUiState.idle;`.
    - Same subtitle simplification as MEMS:
      - `nfbData == null` → `'Run calibration first to enable'`.
      - `nfbData != null` → `'Takes effect on next connect'`.
    - `onChanged: nfbData == null ? null : (val) { log('Productivity: Use NFB Calibration toggled: $val', name: 'Neiry'); ref.read(useCalibrationToggleProvider.notifier).state = val; }` — preserve the `log()` call exactly.
  - In `_ProductivityCard.build`:
    - Replace `final classifier = ref.watch(productivityClassifierProvider);` with two stream watches that already feed the body: `final indexesAsync = ref.watch(productivityIndexesProvider);` and `final metricsAsync = ref.watch(productivityMetricsProvider);` — or, simpler, keep the existing inline `ref.watch(productivityIndexesProvider).when(...)` / `ref.watch(productivityMetricsProvider).when(...)` calls and just delete the wrapping `if (classifier == null) ... else ...[ ... ]` structure.
    - The "Waiting for device..." message now comes from the `loading:` branch of each inner `.when(...)` call — no separate placeholder is needed.
    - The calibration progress bar and the two buttons (`Start Baseline Calibration`, `Reset Fatigue`) move out from inside the deleted `else ...[ ... ]` and become unconditional children of the `Column`.
    - Replace `ref.read(productivityClassifierProvider.notifier).startBaselineCalibration()` with `ref.read(productivityActionsProvider.notifier).startBaselineCalibration()`.
    - Replace `ref.read(productivityClassifierProvider.notifier).resetAccumulatedFatigue()` with `ref.read(productivityActionsProvider.notifier).resetAccumulatedFatigue()`.
    - Preserve both `log('Productivity: …', name: 'Neiry')` calls byte-identical.
  - In `_CardioCard.build`:
    - Replace `final classifier = ref.watch(cardioClassifierProvider);` with `final cardioAsync = ref.watch(cardioStateProvider);`.
    - Delete the `if (classifier == null) ... else ...[ ... ]` split. The Cardio state `when(loading: () => const Text('Waiting for device...'), error: ..., data: ...)` already covers the "no device" placeholder via its `loading` branch.
    - The PPG last-value `ref.watch(cardioPpgProvider).whenOrNull(...)` widget stays exactly as-is — its existing `?? const Text('PPG: —', ...)` fallback handles the no-device case.
    - Keep `ref.listen(cardioCalibratedProvider, (_, next) { if (next.hasValue) ... showSnackBar('Cardio calibration complete') })` unchanged — `cardioCalibratedProvider` now resolves via Task 2.

### Phase 4: Verify

- [x] **Task 7: Compile-check the example app** (depends on Task 6)
  Files: (no edits — verification only)
  - From `example/`, run `flutter analyze`.
  - Confirm zero references remain to: `emotionsClassifierProvider`, `physioClassifierProvider`, `memsClassifierProvider`, `cardioClassifierProvider`, `productivityClassifierProvider`, or any import of the deleted `*_classifier_provider.dart` files.
  - If the analyzer flags any unresolved symbol outside the three screens, `NeiryService`, `classifier_stream_providers.dart`, or `nfb_calibration_provider.dart`, stop and report — fixing it belongs to milestone 94 (`calibration_screen` migration) and is out of scope here.

## Commit Plan
- **Commit 1** (after Tasks 1–3): "Expose physio/cardio calibrated streams and re-add NFB-calibration toggle preferences"
- **Commit 2** (after Tasks 4–6): "Migrate classifiers, MEMS, productivity+cardio screens to NeiryService"
- **Commit 3** (after Task 7): "Verify example app compiles after classifier-screen migration" — skip if Task 7 makes no edits and analyze is already clean.
