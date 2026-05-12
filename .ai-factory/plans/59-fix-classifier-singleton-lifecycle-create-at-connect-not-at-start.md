# Plan: Fix classifier singleton lifecycle — create at connect, not at start

## Context
The Capsule SDK enforces a one-instance-per-device rule for all 6 classifier modules (no `Release`/`Destroy` exists in the C API), so the current "create-at-start / dispose-at-stop" gating crashes the process on the second `Start` press and also delays Android PPG hardware mode switch. Move classifier creation to the connect boundary so each instance lives for the full connection lifetime.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Loosen Dart classifier guards (lib/)

- [x] **Task 1: Cardio classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/cardio_classifier.dart`
  In both factory constructors (`CardioClassifier(...)` and `CardioClassifier.withCalibration(...)`), replace the `if (!device.isStarted)` check and its `StateError('Cannot create CardioClassifier before Device.start()')` message with `if (!device.isConnected)` and `StateError('Cannot create CardioClassifier before Device.connect()')`.

- [x] **Task 2: MEMS classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/mems_classifier.dart`
  Apply the same transformation: every `!device.isStarted` factory guard becomes `!device.isConnected`, and the error message switches from `Device.start()` to `Device.connect()`. Cover all factory constructors in the file.

- [x] **Task 3: Productivity classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/productivity_classifier.dart`
  Same change: `!device.isStarted` → `!device.isConnected`; `StateError('Cannot create ProductivityClassifier before Device.start()')` → `StateError('Cannot create ProductivityClassifier before Device.connect()')` in every factory.

- [x] **Task 4: Emotions classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/emotions_classifier.dart`
  Same change: `!device.isStarted` → `!device.isConnected`; update each `StateError` message from `before Device.start()` to `before Device.connect()`.

- [x] **Task 5: NFB classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/nfb_classifier.dart`
  Same change: `!device.isStarted` → `!device.isConnected`; update each `StateError` message from `before Device.start()` to `before Device.connect()`.

- [x] **Task 6: Physio classifier — guard on isConnected**
  Files: `lib/src/api/classifiers/physio_classifier.dart`
  Same change: `!device.isStarted` → `!device.isConnected`; update each `StateError` message from `before Device.start()` to `before Device.connect()`.

### Phase 2: Move provider creation to connect boundary (example/)

- [x] **Task 7: Cardio provider — drop isStarted gating** (depends on Task 1)
  Files: `example/lib/providers/cardio_classifier_provider.dart`
  In `CardioClassifierNotifier.build()`, remove the `final isStarted = ref.watch(deviceIsStartedProvider);` line and change the null-guard to `if (device == null) return null;`. Remove the now-unused `import 'device_state_providers.dart';` at the top of the file. Keep `ref.read(nfbCalibrationProvider)`, `ref.watch(useCalibrationToggleProvider)`, the create call, and the existing `ref.onDispose(...)` cleanup untouched. Update the doc comment on `CardioClassifierNotifier` to describe the new lifecycle: classifier lives from `Device.connect()` to `Device.disconnect()`, the calibration toggle is safe to flip only while disconnected, and a newly-imported calibration takes effect on the next `Device.disconnect()` → `Device.connect()` cycle (replacing the old `Device.stop()` → `Device.start()` wording).

- [x] **Task 8: MEMS provider — drop isStarted gating** (depends on Task 2)
  Files: `example/lib/providers/mems_classifier_provider.dart`
  Remove the `ref.watch(deviceIsStartedProvider)` line; change the guard to `if (device == null) return null;`. Remove the unused `import 'device_state_providers.dart';`. Update any doc comment referencing `Device.start()`/`Device.stop()` lifecycle to reference `Device.connect()`/`Device.disconnect()` instead.

- [x] **Task 9: Productivity provider — drop isStarted gating** (depends on Task 3)
  Files: `example/lib/providers/productivity_classifier_provider.dart`
  Same transformation as Task 8: drop `isStarted` read, simplify null-guard to device-only, remove the `device_state_providers.dart` import, and update lifecycle comments to `connect`/`disconnect`.

- [x] **Task 10: Emotions provider — drop isStarted gating** (depends on Task 4)
  Files: `example/lib/providers/emotions_classifier_provider.dart`
  Same transformation: drop `isStarted` read, simplify null-guard to device-only, remove the `device_state_providers.dart` import, update lifecycle comments.

- [x] **Task 11: NFB provider — drop isStarted gating** (depends on Task 5)
  Files: `example/lib/providers/nfb_classifier_provider.dart`
  Same transformation: drop `isStarted` read, simplify null-guard to device-only, remove the `device_state_providers.dart` import, update lifecycle comments.

- [x] **Task 12: Physio provider — drop isStarted gating** (depends on Task 6)
  Files: `example/lib/providers/physio_classifier_provider.dart`
  Same transformation: drop `isStarted` read, simplify null-guard to device-only, remove the `device_state_providers.dart` import, update lifecycle comments.

### Phase 3: Update calibration toggle UX

- [x] **Task 13: MEMS screen — toggle gated on idle** (depends on Task 8)
  Files: `example/lib/screens/mems_screen.dart`
  Change `final canEditToggle = uiState != DeviceUiState.started;` to `final canEditToggle = uiState == DeviceUiState.idle;`. Update the disabled-state subtitle string from `'Stop streaming to change this setting'` to `'Disconnect to change this setting'`. Leave the rest of the screen (start/stop button, calibration switch behavior) untouched.

- [x] **Task 14: Productivity/Cardio screen — toggle gated on idle** (depends on Task 9, Task 7)
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  Same two edits: `uiState != DeviceUiState.started` → `uiState == DeviceUiState.idle`; subtitle `'Stop streaming to change this setting'` → `'Disconnect to change this setting'`. Do not touch any other references to `deviceIsStartedProvider` in this file (if any remain — they are for stream/start guards, not toggle gating).

## Commit Plan
- **Commit 1** (after tasks 1-6): "Loosen classifier factory guards to require connected device instead of started"
- **Commit 2** (after tasks 7-12): "Create classifier providers at connect instead of start"
- **Commit 3** (after tasks 13-14): "Gate calibration toggle on disconnected state in example screens"
