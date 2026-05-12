# Plan: Fix "module already exists" crash when toggling Use NFB Calibration

## Context

Toggling the "Use NFB Calibration" `Switch` in the example app triggers `Fatal signal 64` (SIGABRT) on Android. The previous diagnosis ("Riverpod create races onDispose") was wrong: dispose is async and yields at `await _nativeReady`, so the platform-channel order on the previous attempt would still have been create-then-dispose; and even with correct ordering the Capsule SDK exposes **no destroy function** for `clCProductivity` / `clCCardio` / `clCMEMS` — disposal in our bridges only unhooks event callbacks, it does not unregister the classifier from the device. A second `clCProductivity_Create(dev, …)` for the same device therefore hits a "module already exists" abort path inside the Android AAR. iOS appears to tolerate the second `Create` silently; Android does not.

**Triggers of the second `_Create`.** The three classifier notifiers in `example/lib/providers/*` currently `ref.watch` two pieces of mutable state that both fire while the device is streaming: the user-facing `useCalibrationToggleProvider` / `useMemsCalibrationToggleProvider`, **and** `nfbCalibrationProvider`. The latter is mutated by `CalibrationNotifier.importFromFile` (`calibration_provider.dart:121`) and by `_writeToSharedProvider` during `startFull` / `startQuick` (`calibration_provider.dart:141`). So the bug reproduces from two distinct user actions while streamed: (1) flipping the toggle, and (2) importing or running calibration on the Calibration tab. Fixing only the toggle leaves the second SIGABRT path latent.

**Strategy:** respect the SDK's lifecycle. A classifier is owned by `Device` for the duration of streaming; it cannot be hot-swapped while `Device.start()` is active. The fix has three parts:

1. **UX gate** — disable the "Use NFB Calibration" toggle in the example screens whenever the device is in the `started` state, so the toggle can only flip while no classifier is alive (i.e. before `Start` or after `Stop`). This blocks the toggle-driven rebuild. On iOS this is a deliberate UX regression: today iOS users *can* hot-swap calibration mid-stream because the iOS framework swallows the second `_Create`; after this change they no longer can. The behaviour is unified across platforms to match the SDK's documented lifecycle contract.
2. **Make calibration data a build-time snapshot, not a watched dependency** — switch the three classifier notifiers from `ref.watch(nfbCalibrationProvider)` to `ref.read(nfbCalibrationProvider)`. This matches the pattern already in place in `nfb_classifier_provider.dart:22` and ensures `CalibrationNotifier.importFromFile` / `startQuick` / `startFull` cannot trigger a rebuild while the device is streaming. New calibration data takes effect on the next `Device.stop()` → `Device.start()` cycle, symmetric with the toggle lock.
3. **Honest Android-side surface for Productivity** — `clCProductivity_CreateWithIndividualData` is **not** exported by the Android AAR. The current `nativeCreateProductivityWithIndividualData` silently falls back to plain `_Create`, so on Android the toggle would be a feature lie even if it didn't crash. Replace the silent fallback with an explicit `clCError_ModuleIsNotSupported` error and add a Dart-side platform guard in `ProductivityClassifier.withCalibration` so the failure surfaces as a clear `UnsupportedError`. The example provider then catches that `UnsupportedError` and falls back to the non-calibrated factory — Cardio still receives calibration via its real `_CreateCalibrated` symbol.

## Acceptance criterion (manual repro)

On Android, connect to a Headband, run an NFB calibration to populate `nfbCalibrationProvider`, navigate to the Productivity & Cardio screen, then to the MEMS screen:

- The "Use NFB Calibration" `SwitchListTile` must be **non-interactive** (greyed out, with a subtitle that explains *why* it is locked, e.g. "Stop streaming to change this setting") while the device's EEG stream is started; it must become interactive again after `Device.stop()`.
- Toggling the switch **before** start, then starting the device, must not SIGABRT and the corresponding indexes/state stream must continue emitting.
- With the device **already started**, navigating to the Calibration tab and importing a calibration from file (or running `startQuick`) must not SIGABRT — the Productivity, Cardio and MEMS streams must keep emitting from the originally-created classifiers. The newly-imported calibration is expected to take effect only after the next `Stop` → `Start` cycle.
- On Android, attempting to construct `ProductivityClassifier.withCalibration(...)` must throw an `UnsupportedError` with a clear message rather than silently producing a non-calibrated classifier. The example app must not enable the calibrated-Productivity path on Android: the `ProductivityClassifierNotifier` catches the `UnsupportedError` and falls back to the plain `ProductivityClassifier(device)` so neither Productivity nor any sibling classifier dies. The shared toggle remains visible and enabled because it still gates the Cardio classifier (Cardio's calibrated factory is supported on Android).

## Settings

- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Lock the toggle while the device is streaming

- [x] **Task 1: Disable the "Use NFB Calibration" toggle while the device is started in `productivity_cardio_screen.dart`**
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  Add `import '../providers/device_state_providers.dart';` and read `final uiState = ref.watch(deviceUiStateProvider);`. Compute `final canEditToggle = uiState != DeviceUiState.started;`. Update the `SwitchListTile`:
  - Set `onChanged` to `null` (disabled) when `nfbData == null` **or** `!canEditToggle`.
  - Replace the `subtitle` so it shows three states: (a) `nfbData == null` → existing "Run calibration first to enable" message; (b) `nfbData != null && !canEditToggle` → "Stop streaming to change this setting" (grey); (c) otherwise → existing behaviour (use-calibration confirmation or no subtitle).
  - Keep the `value` expression `useCalibration && nfbData != null` unchanged.
  Do not change anything outside the `SwitchListTile`. The intent is: the user must `Stop` before toggling, then `Start` again — which is the only SDK-legal way to apply a new calibration choice.

- [x] **Task 2: Disable the "Use NFB Calibration" toggle while the device is started in `mems_screen.dart`**
  Files: `example/lib/screens/mems_screen.dart`
  Apply the same pattern as Task 1 to the MEMS screen's `SwitchListTile`. Import `device_state_providers.dart`, watch `deviceUiStateProvider`, derive `canEditToggle`, and gate `onChanged` plus the subtitle states identically. The toggle backing this screen is `useMemsCalibrationToggleProvider`; otherwise the structure of the `SwitchListTile` block is the same.

### Phase 2: Make calibration data a build-time snapshot

- [x] **Task 3: Switch `nfbCalibrationProvider` from `ref.watch` to `ref.read` in the three classifier notifiers**
  Files: `example/lib/providers/productivity_classifier_provider.dart`, `example/lib/providers/cardio_classifier_provider.dart`, `example/lib/providers/mems_classifier_provider.dart`
  In each notifier's `build()`, change `final nfbData = ref.watch(nfbCalibrationProvider);` to `final nfbData = ref.read(nfbCalibrationProvider);`. The variable name, the conditional (`useCalibration && nfbData != null`), and every other line in `build()` stay the same. Reference pattern: `nfb_classifier_provider.dart:22` already uses `ref.read(nfbCalibrationProvider)` for the same reason. This snapshots the calibration once at classifier creation; mutations to `nfbCalibrationProvider` (from `CalibrationNotifier.importFromFile` or `_writeToSharedProvider`) no longer trigger a notifier rebuild while the device is streamed. New calibration data takes effect on the next `Device.start()`.
  Do **not** change the `ref.watch(activeDeviceProvider)` / `ref.watch(deviceIsStartedProvider)` / `ref.watch(useCalibrationToggleProvider)` (and `useMemsCalibrationToggleProvider`) lines — those rebuilds are either gated by the toggle lock from Phase 1 or are the legitimate create-on-start signal.

### Phase 3: Honest Android surface for Productivity calibration

- [x] **Task 4: Make `nativeCreateProductivityWithIndividualData` fail explicitly instead of silently falling back to plain `_Create` on Android**
  Files: `android/src/main/cpp/jni_productivity.cpp`
  In the JNI function around lines 70–114, remove the silent-fallback `clCProductivity_Create(dev, &error)` call and the surrounding setup of `clCIndividualNFBData` (the `ts`, `failReason`, `individualFrequency`, …, `upperFrequency` JNI parameters become unused — see below). Replace the body with:
  ```cpp
  clCError error{};
  error.success = false;
  error.code = clCError_ModuleIsNotSupported;
  snprintf(error.message, sizeof(error.message),
           "clCProductivity_CreateWithIndividualData is not exported by the Android Capsule AAR");
  throw_sdk_error(env, &error);
  return 0;
  ```
  Use the `snprintf(error.message, sizeof(error.message), "...")` idiom (the same pattern used elsewhere in the JNI bridges) — `clCError::message` is a fixed-size `char[256]` buffer, so assignment is not an option. Use `clCError_ModuleIsNotSupported` (defined in `official/iOS/CapsuleClient.framework/Headers/CError.h:18`) — it is the semantically correct enum value for "this symbol is not supported by this build of the SDK", and downstream Kotlin code that switches on the code will see the right intent.
  Keep the JNI signature unchanged so the Kotlin bridge does not need re-binding. The now-unused parameters (`ts`, `failReason`, `individualFrequency`, `userIndividualFrequency`, `lowerFrequency`, `upperFrequency`, and any others previously consumed) must be silenced for the build: either mark them `[[maybe_unused]]` in the JNI signature or add `(void)paramName;` lines at the top of the function body. Pick whichever matches the file's existing style; the goal is to not regress the build under `-Werror`.
  Above the function add a single-line marker: `// TODO(neiry-aar): restore _CreateWithIndividualData path when the AAR exports it.`

- [x] **Task 5: Add a platform guard in `ProductivityClassifier.withCalibration` that throws `UnsupportedError` on Android**
  Files: `lib/src/api/classifiers/productivity_classifier.dart`
  At the top of the `ProductivityClassifier.withCalibration` factory (around line 69), after the `device.isStarted` guard, add:
  ```dart
  if (Platform.isAndroid) {
    throw UnsupportedError(
      'ProductivityClassifier.withCalibration is not supported on Android: '
      'clCProductivity_CreateWithIndividualData is not exported by the Capsule AAR. '
      'Use ProductivityClassifier(device) instead.',
    );
  }
  ```
  Add `import 'dart:io' show Platform;` at the top of the file. Update the doc comment on the factory to call out the Android limitation in one sentence. Do not change the plain `ProductivityClassifier(device)` factory or the `_` constructor.

### Phase 4: Reflect the new constraint in the example providers

- [x] **Task 6: Update doc comments and add a defensive Android fallback in `productivity_classifier_provider.dart`**
  Files: `example/lib/providers/productivity_classifier_provider.dart`, `example/lib/providers/cardio_classifier_provider.dart`, `example/lib/providers/mems_classifier_provider.dart`
  In each notifier's class doc comment, replace the sentence "Re-creates the classifier whenever the device, started-state, calibration toggle, or NFB calibration data changes." with a paragraph that states: (a) the classifier is created on `Start` and destroyed on `Stop` — the Capsule SDK has no per-classifier destroy, so re-creating against an already-streaming device aborts on Android; (b) the calibration toggle is therefore only safe to flip while the device is **not** started, which the example screens enforce by disabling the `Switch`; (c) calibration data is read once at build time (see Task 3) — a new calibration is picked up on the next `Stop` → `Start` cycle; (d) on Android, individual-NFB Productivity calibration is not available — the toggle still controls Cardio.
  Additionally in `productivity_classifier_provider.dart` only:
  - Add `import 'package:flutter/foundation.dart' show debugPrint;` (neither `flutter_riverpod` nor `neiry_kit` re-exports `debugPrint` and the file does not currently import `flutter/material.dart`, so an explicit import is required).
  - Replace the existing `final ProductivityClassifier classifier; if (useCalibration && nfbData != null) { classifier = ProductivityClassifier.withCalibration(device, nfbData); } else { classifier = ProductivityClassifier(device); }` block with:
    ```dart
    final ProductivityClassifier classifier;
    if (useCalibration && nfbData != null) {
      try {
        classifier = ProductivityClassifier.withCalibration(device, nfbData);
      } on UnsupportedError {
        debugPrint(
          'ProductivityClassifier.withCalibration unsupported on this platform; '
          'falling back to plain factory',
        );
        classifier = ProductivityClassifier(device);
      }
    } else {
      classifier = ProductivityClassifier(device);
    }
    ```
    The `try` must wrap **only** the calibrated factory call — not the `else` branch and not the `ref.onDispose(...)` block that follows.
  - Do not modify the `ref.onDispose(() { classifier.dispose(); })` block.

## Commit Plan

- **Commit 1** (after tasks 1–3): "Lock NFB calibration toggle while streaming and snapshot calibration data"
- **Commit 2** (after tasks 4–6): "Surface Android Productivity calibration as unsupported with explicit error"
