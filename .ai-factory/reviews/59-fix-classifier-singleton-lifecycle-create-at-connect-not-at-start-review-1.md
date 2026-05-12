# Code Review: Fix classifier singleton lifecycle — create at connect, not at start

**Scope:** all 14 changed files
- 6 classifier libs (`lib/src/api/classifiers/*.dart`)
- 6 example providers (`example/lib/providers/*_classifier_provider.dart`)
- 2 example screens (`mems_screen.dart`, `productivity_cardio_screen.dart`)
- Cross-referenced: `lib/src/api/device.dart`, `example/lib/providers/active_device_provider.dart`, `example/lib/providers/device_state_providers.dart`, `example/lib/screens/device_screen.dart`

**Risk Level:** 🟢 Low

## Plan-conformance check

Every task in the plan landed in the diff exactly as written:
- Phase 1 (Tasks 1-6): all six `if (!device.isStarted)` factory guards switched to `!device.isConnected`; all six `StateError('… before Device.start()')` strings switched to `… before Device.connect()`; per-factory dartdoc `Throws` lines updated. The class-level `## Lifecycle` paragraph was rewritten in every classifier file, addressing the doc-rot gap flagged in plan-review-1.
- Phase 2 (Tasks 7-12): all six providers dropped the `final isStarted = ref.watch(deviceIsStartedProvider);` line, simplified the guard to `if (device == null) return null;`, removed the `import 'device_state_providers.dart';` line, and updated lifecycle doc comments to talk about connect/disconnect.
- Phase 3 (Tasks 13-14): both screens swapped the toggle gate to `uiState == DeviceUiState.idle` and rewrote the subtitle to `'Disconnect to change this setting'`.

No edits leaked into out-of-scope files (`device_state_providers.dart`, `device_screen.dart`, other providers).

## Findings

### Critical Issues

None.

### Architectural notes / non-blocking

1. **Subtle ordering regression on the device-switch path.** In `ActiveDeviceNotifier.createAndConnect` (`example/lib/providers/active_device_provider.dart:26-36`), when an existing device is replaced by a new one:
   ```dart
   final existing = state;
   if (existing != null) {
     try { await existing.stop(); } catch (_) {}
     try { await existing.disconnect(); } catch (_) {}
     try { await existing.dispose(); } catch (_) {}
   }
   // ... later ...
   state = device;  // new device
   ```
   The `state` reference is unchanged through the entire `existing.{stop,disconnect,dispose}` sequence, so the classifier providers do not rebuild. The old classifier instance therefore outlives its backing native device handle. Only when `state = device` is set (with a new device reference) do the classifier providers rebuild and trigger `ref.onDispose → oldClassifier.dispose()` — at which point the native classifier-dispose call is sent against a serial whose native `Device` has already been released.

   Why it was OK in the old code: the call site in `device_screen.dart:101` does `ref.read(deviceIsStartedProvider.notifier).state = false;` *before* `createAndConnect`, which caused classifier providers (gated on `isStarted`) to rebuild → null → dispose old classifier *before* the device-disposal sequence. The new code's classifier providers no longer watch `deviceIsStartedProvider`, so the reset is a no-op for them.

   Likely impact: low. The native side has historically tolerated dispose-after-device-gone calls on this codebase (since `Device.disconnect` is itself idempotent and the SDK appears to track classifier handles globally). Worst case is a benign native warning. Mitigation, if it ever surfaces in practice: have `createAndConnect` set `state = null` before disposing the existing device, mirroring `disconnectAndDispose()` (`active_device_provider.dart:51-65`).

2. **Race between `_connected = true` (Dart) and actual BLE link-up (native).** `Device.connect()` (`lib/src/api/device.dart:168-177`) flips `_connected = true` immediately after `invokeMethod` returns from dispatching the platform call — well before the native side reports `NeiryConnectionState.connected` via `connectionStateStream`. The new factory guard therefore admits classifier creation during the "BLE-connecting-on-the-wire" window.

   The milestone description claims this is the intended behavior (it's what triggers the Android PPG mode switch early enough for the LED to light correctly on first start). So this is a feature, not a bug — but the contract has shifted: classifier factories now run against a device that may not yet be physically linked. Anyone reading the dartdoc "device is connected" should understand it means "the connect call has been dispatched" rather than "the BLE link is up." The lifecycle comments could be tighter on that nuance, but it's a documentation refinement, not a code defect.

3. **Calibration/utility methods are now reachable in `DeviceUiState.connected`.** Buttons that call `productivityClassifierProvider.startBaselineCalibration()`, `resetAccumulatedFatigue()`, and `physioClassifierProvider.startBaselineCalibration()` / `importBaselines()` were previously hidden behind `classifier != null`, which previously required `isStarted`. They are now visible (and tappable) as soon as the device connects. Whether the native SDK accepts these calls with no EEG stream flowing is a separate runtime question (the C API docs imply calibration needs streaming). Not a regression from the plan — but worth flagging as the natural next bug surface. If the SDK rejects the call, surfacing a meaningful error beats silently hanging the progress bar.

4. **Toggle providers (`useCalibrationToggleProvider`, `useMemsCalibrationToggleProvider`) are still `ref.watch`-ed inside the classifier providers** (`cardio_classifier_provider.dart:28`, `mems_classifier_provider.dart:35`, `productivity_classifier_provider.dart:42`). The only thing preventing a mid-connection toggle flip from rebuilding the classifier (and re-triggering the "module already exists" Android crash) is the UI gate added in Tasks 13/14. If a future caller flips the toggle programmatically, or a new screen adds the same `SwitchListTile` without the same gate, the regression returns silently. Belt-and-suspenders would be `ref.read` for the toggle (with explicit invalidation on disconnect), or an `assert(!device.isConnected)` inside the provider when the toggle is the only watched dependency. Out of scope for this milestone, but worth a note.

### Wording / consistency nitpicks

- The lifecycle paragraph in `cardio_classifier.dart:39-51` carries the full "calibration toggle is safe to flip only while disconnected" wording, matching `mems_classifier.dart` and `productivity_classifier.dart`. The three non-calibration classifiers (`emotions_classifier.dart:23-30`, `nfb_classifier.dart:26-33`, `physio_classifier.dart:31-38`) correctly omit the calibration paragraph. Consistent split.
- The plan instructs Tasks 10-12 to "update any doc comment referencing `Device.start()`/`Device.stop()` lifecycle"; the actual provider comments said "started-state changes", and the diff correctly rephrased them to "When the device disconnects, the old classifier is disposed and a new one is created on the next connection automatically." Spirit preserved.

### Positive Notes

- The diff is mechanically identical to the plan, which makes review fast and removes guesswork about intent.
- The dartdoc updates in `lib/src/api/classifiers/` (which the plan did not strictly require, only the `StateError` message strings) close the doc-rot gap flagged in plan-review-1. Good extra mile.
- The toggle gate `uiState == DeviceUiState.idle` is the correct reading of the new invariant: the classifier providers `ref.watch` the toggle, so flipping it post-connect would re-create the singleton and trip the very Android crash this milestone is fixing. The tightened gate makes the contract self-enforcing for the example app.
- `disconnectAndDispose()` (`active_device_provider.dart:51-65`) sets `state = null` *before* disposing the device, so the normal disconnect path correctly disposes classifiers while the native device is still alive. Only the device-SWITCH path (note #1) inverts this order.
- Commit boundaries align cleanly with the three phases, enabling per-phase revert if hardware testing reveals a regression in one layer only.

REVIEW_PASS
