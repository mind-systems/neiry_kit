# Plan: MEMS tab in example app

## Context

Add a 6th tab `/mems` to the example app's `StatefulShellRoute` that displays live accelerometer and gyroscope data from the `MEMSClassifier`, with an optional NFB-calibration toggle.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Provider layer

- [x] **Task 1: Create MEMS classifier provider**
  Files: `example/lib/providers/mems_classifier_provider.dart`
  Create `MEMSClassifierNotifier extends Notifier<MEMSClassifier?>` following the exact pattern in `cardio_classifier_provider.dart`:
  - `build()` watches `activeDeviceProvider`, `deviceIsStartedProvider`, `nfbCalibrationProvider`, and a new `useMemsCalibrationToggleProvider` (`StateProvider<bool>`, default `false`).
  - Returns `null` when device is null or not started.
  - When `useCalibration && nfbData != null`, instantiate via `MEMSClassifier.withCalibration(device, nfbData)`; otherwise `MEMSClassifier(device)`.
  - `ref.onDispose` captures the local classifier instance and calls `classifier.dispose()`.
  - Export as `memsClassifierProvider = NotifierProvider<MEMSClassifierNotifier, MEMSClassifier?>`.

- [x] **Task 2: Create MEMS data stream provider**
  Files: `example/lib/providers/mems_classifier_provider.dart` (append to same file)
  Add `memsProvider` as a `StreamProvider<List<MemsSample>>`:
  - Watches `memsClassifierProvider`; returns `Stream.empty()` when null.
  - Pipes `classifier.memsStream.throttleTime(const Duration(milliseconds: 100))` from `rxdart` (10 Hz, matching `eegProvider` in `stream_providers.dart`).
  - Import `rxdart` and `neiry_kit`.

### Phase 2: UI layer

- [x] **Task 3: Create MEMS screen widget**
  Files: `example/lib/screens/mems_screen.dart`
  Create `MemsScreen extends ConsumerWidget` following the layout patterns in `productivity_cardio_screen.dart`:
  - AppBar title: `'MEMS'`.
  - `SwitchListTile` for "Use NFB Calibration" — watches `nfbCalibrationProvider` and `useMemsCalibrationToggleProvider`; disabled (`onChanged: null`) when `nfbData == null`; toggling writes to `useMemsCalibrationToggleProvider.notifier.state` which invalidates `memsClassifierProvider` automatically (it watches the toggle).
  - When `memsClassifierProvider` is null, show `'Waiting for device...'` text.
  - When classifier is available, watch `memsProvider`:
    - `loading:` state shows `'Waiting for MEMS data...'`.
    - `error:` state shows error text.
    - `data:` state extracts the last sample from the list (`samples.last`) and renders two `Card` widgets:
      - **Accelerometer Card** — title "Accelerometer", three rows: X / Y / Z from `sample.accelerometer`, values formatted with `toStringAsFixed(4)`.
      - **Cardio Card** — title "Gyroscope", three rows: X / Y / Z from `sample.gyroscope`, values formatted with `toStringAsFixed(4)`.
  - Reuse `_MetricRow`-style helper locally (private `_AxisRow` widget with label + value) rather than importing private widgets from another screen.

- [x] **Task 4: Add MEMS tab to router and navigation bar**
  Files: `example/lib/router.dart`
  - Import `mems_screen.dart`.
  - Add a 6th `StatefulShellBranch` with `GoRoute(path: '/mems', builder: (_, _) => const MemsScreen())` — insert it as the 5th branch (index 4), before `/calibration` which moves to index 5, keeping Calibration as the last tab.
  - Add a `NavigationDestination(icon: Icon(Icons.sensors), label: 'MEMS')` at position index 4 in the `destinations` list (before Calibration).

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add MEMS classifier and throttled stream providers"
- **Commit 2** (after tasks 3-4): "Add MEMS tab with accelerometer and gyroscope display"
