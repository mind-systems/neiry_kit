# Plan: Physio + Emotions tab

## Context

Replace the stub `ClassifiersScreen` with a fully functional tab showing two classifier cards: an Emotions card (continuous updates, no timestamp) on top, and a Physio card (2-minute updates with last-updated timestamp, opacity dimming, signal quality row, and baselines import/export) below.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Providers and file manager

- [x] **Task 1: Physio classifier provider**
  Files: `example/lib/providers/physio_classifier_provider.dart`
  Follow the two-layer pattern from `nfb_classifier_provider.dart`:
  - `physioClassifierProvider` as `NotifierProvider<PhysioClassifierNotifier, PhysioClassifier?>` — gates on `activeDeviceProvider != null` and `deviceIsStartedProvider == true`; returns `null` otherwise; creates `PhysioClassifier(device)` when both conditions met; registers `ref.onDispose(() => classifier.dispose())`.
  - `physioStateProvider` as `StreamProvider<PhysiologicalStatesValue>` — watches `physioClassifierProvider`; returns `Stream.empty()` when classifier is null, otherwise `classifier.stateStream`.
  - `physioCalibrationProgressProvider` as `StreamProvider<double>` — wraps `classifier.calibrationProgress`; `Stream.empty()` when null.
  - `physioCalibratedProvider` as `StreamProvider<PhysiologicalStatesBaselines>` — wraps `classifier.calibrated`; `Stream.empty()` when null. When this emits, also write the value to a `physioBaselinesProvider` (`StateProvider<PhysiologicalStatesBaselines?>`) so the last baselines are accessible for export.
  - `physioBaselinesProvider` as `StateProvider<PhysiologicalStatesBaselines?>` — holds the last calibrated or imported baselines; shared state for export button enablement.
  - Add methods on the notifier: `startBaselineCalibration()` delegates to `classifier.startBaselineCalibration()`; `importBaselines(PhysiologicalStatesBaselines)` delegates to `classifier.importBaselines(baselines)` and writes to `physioBaselinesProvider`.

- [x] **Task 2: Emotions classifier provider**
  Files: `example/lib/providers/emotions_classifier_provider.dart`
  Same two-layer pattern:
  - `emotionsClassifierProvider` as `NotifierProvider<EmotionsClassifierNotifier, EmotionsClassifier?>` — gates on `activeDeviceProvider != null` and `deviceIsStartedProvider == true`; creates `EmotionsClassifier(device)` when valid; `ref.onDispose(() => classifier.dispose())`.
  - `emotionsStateProvider` as `StreamProvider<EmotionsStates>` — watches `emotionsClassifierProvider`; `Stream.empty()` when null, otherwise `classifier.stateStream`.
  No calibration, no baselines, no file management.

- [x] **Task 3: Physio baselines file manager** (depends on Task 1)
  Files: `example/lib/providers/physio_baselines_file_manager.dart`
  Follow the `CalibrationFileManager` pattern — `abstract final class PhysioBaselinesFileManager` with static methods:
  - `exportToFile(PhysiologicalStatesBaselines baselines)` — writes `physio_baselines_<millis>.json` to `getApplicationDocumentsDirectory()` via `jsonEncode(baselines.toMap())`; returns `File`.
  - `importFromFile()` — opens `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'])`; reads file; `jsonDecode` + `PhysiologicalStatesBaselines.fromMap()`; returns `PhysiologicalStatesBaselines?` (null if user cancels).

### Phase 2: Classifiers screen

- [x] **Task 4: Emotions card** (depends on Tasks 2)
  Files: `example/lib/screens/classifiers_screen.dart`
  Replace the stub `ClassifiersScreen` with a `ConsumerWidget` containing a `SingleChildScrollView` with a `Column` of two cards. Build the Emotions card first (top position):
  - `_EmotionsCard` as a private `ConsumerWidget`.
  - Watch `emotionsClassifierProvider`: if null, show `Text('Waiting for device...')`.
  - When classifier exists, watch `emotionsStateProvider` with `.when(loading: ..., error: ..., data: ...)`:
    - `loading` → `Text('Waiting for Emotions data...')`
    - `error` → `Text('Error: $e')`
    - `data` → five metric rows: Attention, Relaxation, Cognitive Load, Cognitive Control, Self-Control. Use the `_MetricRow` helper pattern from `_BandRow` in `calibration_screen.dart`: `Row` with fixed-width label `SizedBox` + `Text(value?.toStringAsFixed(3) ?? '—')`.
  - No timestamp label, no staleness indicator — Emotions updates continuously.
  - Card header: bold "Emotions" title text.
  - Below the Emotions card, add a placeholder `SizedBox()` for the Physio card (Task 5 fills it in).

- [x] **Task 5: Physio card with timestamp, opacity, signal quality, and baselines** (depends on Tasks 1, 3, 4)
  Files: `example/lib/screens/classifiers_screen.dart`
  Add `_PhysioCard` as a private `ConsumerWidget` below the Emotions card:
  - Watch `physioClassifierProvider`: if null, show `Text('Waiting for device...')`.
  - When classifier exists, watch `physioStateProvider` with `.when`:
    - `loading` → wrap entire card content in `Opacity(opacity: 0.5)` and show `Text('Waiting for first update...')`. This communicates the ~2-minute wait.
    - `error` → `Text('Error: $e')`
    - `data` → full-opacity content with:
      - Five metric rows: Relaxation, Fatigue, Concentration, Involvement, Stress (same `_MetricRow` pattern; skip the `none` field — it's an internal SDK placeholder).
      - A `Divider()` followed by a "Signal Quality" section: two rows showing `nfbArtifacts` and `cardioArtifacts` bools — `Icon(Icons.check_circle, color: Colors.green)` when `false` (no artifacts = good signal), `Icon(Icons.error, color: Colors.red)` when `true` (artifacts present = bad signal). Labels: "NFB" and "Cardio".
      - A "Last updated: HH:MM:SS" label below the signal quality section. Format the `PhysiologicalStatesValue.timestamp` as `HH:mm:ss` using `DateFormat` from `intl` or manual `String` formatting (prefer manual to avoid adding a dependency: `'${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:${t.second.toString().padLeft(2,'0')}'`).
  - Below the data section, add baselines action buttons:
    - **Start Baseline Calibration** (`ElevatedButton`) — calls `ref.read(physioClassifierProvider.notifier).startBaselineCalibration()`. Disabled when classifier is null.
    - **Import Baselines** (`OutlinedButton`) — calls `PhysioBaselinesFileManager.importFromFile()`, then `ref.read(physioClassifierProvider.notifier).importBaselines(result)` and writes to `physioBaselinesProvider`. Show `SnackBar` on success.
    - **Export Baselines** (`OutlinedButton`) — enabled only when `physioBaselinesProvider` is not null. Calls `PhysioBaselinesFileManager.exportToFile(baselines)`. Show `SnackBar` with file path on success.
  - Watch `physioCalibrationProgressProvider` — when loading/active, show a `LinearProgressIndicator` with the progress value (0.0–1.0) above the buttons. When `physioCalibratedProvider` emits, show a brief "Baselines calibrated" confirmation and write to `physioBaselinesProvider`.
  - Card header: bold "Physiological States" title text.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add Physio and Emotions classifier providers with baselines file manager"
- **Commit 2** (after tasks 4-5): "Build Physio + Emotions classifiers screen with timestamp, signal quality, and baselines import/export"
