# Plan: NfbClassifier

## Context

Add the NFB brain-wave classifier Dart API class — the first classifier in the plugin. It wraps the native `clCNFB` lifecycle (create/destroy) and exposes two EventChannel-backed streams for state updates and errors.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel contract

- [x] **Task 1: Add `dispose` to `ClassifierMethods`**
  Files: `lib/src/channel/channel_names.dart`
  `ClassifierMethods` currently has `create`, `createCalibrated`, and calibration methods but no way to destroy a classifier. Add `static const String dispose = 'dispose';` to `ClassifierMethods`. This will be used by all classifier classes (NFB, Physio, Emotions, Productivity, Cardio) to release the native C handle.

### Phase 2: Classifier implementation

- [x] **Task 2: Create NfbClassifier class** (depends on Task 1)
  Files: `lib/src/api/classifiers/nfb_classifier.dart`
  Create the `classifiers/` subdirectory under `lib/src/api/` and add `nfb_classifier.dart`. Follow the `DeviceLocator` error-handling pattern and `Device` stream patterns:

  **Factory constructor:**
  - `factory NfbClassifier(Device device, {IndividualNfbData? calibration})` — guards that the device's EEG stream is active (`device.isStarted`), throwing `StateError('Cannot create NfbClassifier before Device.start()')` if not. Then delegates to the private `NfbClassifier._()` constructor.

  **Private constructor (`NfbClassifier._`):**
  - Stores `device.serial` as `_serial`.
  - Fires (without awaiting) the native creation call as `late final Future<void> _nativeReady`, using the `DeviceLocator` error-capture pattern — chain `.catchError()` on the platform call to store the error in an `Object? _createError` field instead of leaving it unhandled:
    - Without calibration: `_channel.invokeMethod<void>(ClassifierMethods.create, {NeiryArgs.serial: _serial}).catchError((Object error) { _createError = error; })`
    - With calibration: `_channel.invokeMethod<void>(ClassifierMethods.createCalibrated, {NeiryArgs.serial: _serial, NeiryArgs.calibrationData: calibration.toMap()}).catchError((Object error) { _createError = error; })`

  **Guards:**
  - `_checkReady()` — throws `StateError('NfbClassifier creation failed: $_createError')` when `_createError != null`. Called before accessing streams.
  - `_checkNotDisposed()` — throws `StateError('NfbClassifier has been disposed')` when `_disposed` is true.

  **MethodChannel:** `static const _channel = MethodChannel(NeiryChannels.nfb)` — same one-channel-per-module pattern as `Device`.

  **Streams** — use `late final` + private `_eventStream<T>` helper (same as `Device._eventStream`), passing `{NeiryArgs.serial: _serial}` as broadcast stream arguments:
  - `_stateStream` → `EventChannel(NeiryEvents.nfbState)`, decoded with `NfbUserState.fromMap`
  - `_errorStream` → `EventChannel(NeiryEvents.nfbError)`, decoded as `(map) => map['message'] as String` (same pattern as `Device._errorStream`)

  **Public getters** — `stateStream` and `errorStream` call `_checkNotDisposed()` then `_checkReady()`, then return the private `late final` field.

  **Dispose:**
  - `Future<void> dispose()` — idempotent guard (`if (_disposed) return`), sets `_disposed = true`, awaits `_nativeReady` (always completes normally thanks to `.catchError()`), then checks `_createError` — if non-null, returns early (nothing to destroy on native side); otherwise calls `_channel.invokeMethod<void>(ClassifierMethods.dispose, {NeiryArgs.serial: _serial})`.

  **Imports:** `dart:async`, `flutter/services.dart`, `../device.dart`, `../../channel/channel_names.dart`, `../../models/nfb_user_state.dart`, `../../models/individual_nfb_data.dart`.

### Phase 3: Export

- [x] **Task 3: Export NfbClassifier from barrel** (depends on Task 2)
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/classifiers/nfb_classifier.dart';` to the barrel file. Place it after the existing `device_locator.dart` export to keep API classes grouped together.
