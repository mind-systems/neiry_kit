# Plan: Device Dart API

## Context

Implement the `Device` class — the Dart API that wraps the native `clCDevice_*` lifecycle, exposes typed data streams backed by EventChannels, provides query getters for device properties, and enforces the connect→start state machine. This is the second core API class after `DeviceLocator`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Signal data models

- [x] **Task 1: Create EegData, PsdData, EegArtifactData, ResistanceData models**
  Files: `lib/src/models/eeg_data.dart`, `lib/src/models/psd_data.dart`, `lib/src/models/eeg_artifact_data.dart`, `lib/src/models/resistance_data.dart`

  Create four new `@immutable` model classes following the exact conventions in existing models (e.g. `NfbUserState`, `DeviceInfo`). Each class: `@immutable` annotation via `package:flutter/foundation.dart`, `const` named-parameter constructor, `factory ClassName.fromMap(Map<Object?, Object?> map)`.

  **`EegData`** (`eeg_data.dart`) — mirrors data from `clCEEGTimedData` accessor functions:
  - `DateTime timestamp` — from `map['ts'] as int` (millisecondsSinceEpoch), timestamp of the first sample
  - `List<List<double>> rawValues` — `[channel][sample]`, microvolts. Decode from `map['rawValues']` as `List<List>`, cast inner elements to `double`
  - `List<List<double>> processedValues` — same shape, artifact-filtered values (empty lists in Resistance mode)
  - `int channelCount` — from `map['channelCount'] as int`
  - `int sampleCount` — from `map['sampleCount'] as int`

  **`PsdData`** (`psd_data.dart`) — mirrors data from `clCPSDData` accessor functions:
  - `DateTime timestamp` — from `map['ts'] as int`
  - `List<List<double>> values` — `[channel][frequencyBin]`, PSD power values
  - `List<double> frequencies` — frequency bin centers in Hz, length = `frequencyCount`
  - `int channelCount`, `int frequencyCount`
  - Band bounds (all non-nullable `double`): `deltaLower`, `deltaUpper`, `thetaLower`, `thetaUpper`, `alphaLower`, `alphaUpper`, `smrLower`, `smrUpper`, `betaLower`, `betaUpper`
  - Individual bounds (nullable, use `orNull` from `internal/sentinel.dart`): `double? individualAlphaLower`, `double? individualAlphaUpper`, `double? individualBetaLower`, `double? individualBetaUpper`

  **`EegArtifactData`** (`eeg_artifact_data.dart`) — mirrors data from `clCEEGArtifacts` accessor functions:
  - `DateTime timestamp` — from `map['ts'] as int`
  - `List<int> artifacts` — per-channel artifact flag byte (uint8), from `map['artifacts']`
  - `List<double> qualities` — per-channel EEG signal quality (float), from `map['qualities']`
  - `int channelCount` — from `map['channelCount'] as int`

  **`ResistanceData`** (`resistance_data.dart`) — mirrors data from `clCResistance` accessor functions:
  - `List<String> channelNames` — electrode names, from `map['channelNames']`
  - `List<double> values` — resistance per channel in kOhm (confirmed by Doxygen: below 500 kOhm = good, above 1000 kOhm = bad). Add doc comment: `/// Resistance per channel in kOhm.`
  - `int channelCount` — from `map['channelCount'] as int`
  - No timestamp (the C API has no timestamp accessor for `clCResistance`)

### Phase 2: Device class

- [x] **Task 2: Create Device class skeleton with lifecycle methods and state machine** (depends on Task 1)
  Files: `lib/src/api/device.dart`, `lib/src/channel/channel_names.dart`, `test/channel_names_test.dart`

  **Add to `NeiryArgs`** in `channel_names.dart`:
  - `static const String bipolarChannels = 'bipolarChannels';` — needed for `connect()` arguments

  **Update `test/channel_names_test.dart`:** Append `NeiryArgs.bipolarChannels` to the `NeiryArgs` uniqueness test list (the `keys` array inside `group('NeiryArgs — unique', ...)`), so the new constant is covered by the existing uniqueness check.

  **Create `lib/src/api/device.dart`** with the `Device` class. Follow `DeviceLocator` conventions: imports from `../channel/channel_names.dart`, `../channel/enums.dart`, and model files.

  **Class doc comment:** Add a doc comment on `Device` noting that concurrent stream subscriptions on multiple Device instances are not supported, because all EventChannels use shared static channel names and Flutter's `EventChannel` supports only one active `receiveBroadcastStream` per channel name.

  **Constructor:**
  - `Device({required this.serial})` — public named-parameter constructor (not a singleton — multiple devices are possible). Stores the serial. No native call in constructor (native handle was already created by `DeviceLocator.createDevice()`).
  - `final String serial`

  **Channels:**
  - `static const _channel = MethodChannel(NeiryChannels.device)` — all lifecycle and getter MethodChannel calls go here

  **State tracking fields:**
  - `bool _disposed = false`
  - `bool _connected = false` — set `true` after successful `connect()`, reset on `disconnect()` and on hardware-initiated disconnect from stream
  - `bool _started = false` — set `true` after successful `start()`, reset on `stop()` and disconnect
  - `NeiryConnectionState _connectionState = NeiryConnectionState.disconnected`
  - `NeiryDeviceMode? _mode` — cached from mode stream
  - `int? _battery` — cached from battery stream
  - `List<StreamSubscription<dynamic>>? _stateSubscriptions` — internal listeners for state tracking, created in `connect()`

  **Guards** (same pattern as `DeviceLocator`):
  - `void _checkNotDisposed()` — throws `StateError('Device has been disposed')` if `_disposed`
  - `void _checkConnected()` — throws `DeviceNotConnectedException()` (from `neiry_exception.dart`) if `!_connected`

  **Lifecycle methods** — each calls `_checkNotDisposed()` first, passes `{NeiryArgs.serial: serial}` merged with any extra args:
  - `Future<void> connect({bool bipolarChannels = false})` — invokes `DeviceMethods.connect` with `{NeiryArgs.serial: serial, NeiryArgs.bipolarChannels: bipolarChannels}`. On success, sets `_connected = true` and calls `_startStateTracking()` (Task 3 will implement this).
  - `Future<void> disconnect()` — invokes `DeviceMethods.disconnect`. On success, calls `_stopStateTracking()`, sets `_started = false`, `_connected = false`, resets `_connectionState`, `_mode`, `_battery` to defaults.
  - `Future<void> start()` — calls `_checkConnected()` then invokes `DeviceMethods.start`. On success, sets `_started = true`.
  - `Future<bool> stop()` — invokes `DeviceMethods.stop`, returns the `bool` result from native. On success, sets `_started = false`.

  **Dispose:**
  - `Future<void> dispose()` — sets `_disposed = true` early, calls `_stopStateTracking()`, invokes `DeviceMethods.disconnect` on the native side (idempotent if already disconnected), resets all state. Follow the `DeviceLocator.dispose()` pattern of guarding against already-released state.

  **Stub `_startStateTracking()` and `_stopStateTracking()`** as empty methods — Task 3 fills them in.

- [x] **Task 3: Add all stream getters and internal state tracking** (depends on Task 2)
  Files: `lib/src/api/device.dart`

  **Private stream helper:**
  Create a reusable `_eventStream<T>` method that opens an EventChannel, passes `serial` as argument, and maps raw events to typed models. All 8 streams follow this pattern:
  ```dart
  Stream<T> _eventStream<T>(EventChannel channel, T Function(Map<Object?, Object?>) decode) {
    return channel
        .receiveBroadcastStream({NeiryArgs.serial: serial})
        .map((raw) => decode(raw as Map<Object?, Object?>));
  }
  ```

  **Cached streams** — use `late final` fields so each `receiveBroadcastStream` is called exactly once per stream per Device instance. Add `_checkNotDisposed()` call inside a getter that delegates to the `late final` backing field:

  State streams:
  - `connectionStateStream` → `EventChannel(NeiryEvents.connectionStatus)`, decode: `NeiryConnectionState.fromCode(map['state'] as int)`
  - `modeChangedStream` → `EventChannel(NeiryEvents.modeSwitched)`, decode: `NeiryDeviceMode.fromCode(map['mode'] as int)`

  Data streams:
  - `eegStream` → `EventChannel(NeiryEvents.eeg)`, decode: `EegData.fromMap`
  - `psdStream` → `EventChannel(NeiryEvents.psd)`, decode: `PsdData.fromMap`
  - `artifactsStream` → `EventChannel(NeiryEvents.eegArtifacts)`, decode: `EegArtifactData.fromMap`
  - `resistanceStream` → `EventChannel(NeiryEvents.resistance)`, decode: `ResistanceData.fromMap`
  - `batteryStream` → `EventChannel(NeiryEvents.battery)`, decode: `map['charge'] as int`
  - `errorStream` → `EventChannel(NeiryEvents.error)`, decode: `map['message'] as String`

  **Internal state tracking — `_startStateTracking()`:**
  Called from `connect()`. Subscribes to `connectionStateStream`, `modeChangedStream`, and `batteryStream`. Stores subscriptions in `_stateSubscriptions`. Updates:
  - `_connectionState` from connection events. On `disconnected` → also reset `_connected = false`, `_started = false` (hardware-initiated disconnect)
  - `_mode` from mode events
  - `_battery` from battery events

  **`_stopStateTracking()`:** Cancels all subscriptions in `_stateSubscriptions` and sets it to `null`.

  **Dispose update:** Ensure `dispose()` calls `_stopStateTracking()` before invoking native disconnect (already stubbed in Task 2).

- [x] **Task 4: Add query getters** (depends on Task 2)
  Files: `lib/src/api/device.dart`

  All async getters call `_checkNotDisposed()`, then invoke the corresponding `DeviceMethods.*` on `_channel` with `{NeiryArgs.serial: serial}`. Follow the `DeviceLocator` MethodChannel invocation pattern.

  **Cached sync getters** (no native call, read from internal state):
  - `int? get battery` → returns `_battery`
  - `NeiryDeviceMode? get mode` → returns `_mode`
  - `NeiryConnectionState get connectionState` → returns `_connectionState`
  - `bool get isConnected` → returns `_connected`
  - `bool get isStarted` → returns `_started`
  - `bool get isValid` → returns `!_disposed`

  **Async MethodChannel getters** — each calls `_checkNotDisposed()` + `_checkConnected()`:
  - `Future<DeviceInfo> getInfo()` → invokes `DeviceMethods.getInfo`, decodes result with `DeviceInfo.fromMap(result as Map<Object?, Object?>)`
  - `Future<double> getEEGSampleRate()` → invokes `DeviceMethods.getEEGSampleRate`, returns `result as double`
  - `Future<double> getPPGSampleRate()` → invokes `DeviceMethods.getPPGSampleRate`, returns `result as double`
  - `Future<double> getMEMSSampleRate()` → invokes `DeviceMethods.getMEMSSampleRate`, returns `result as double`
  - `Future<int> getPPGIrAmplitude()` → invokes `DeviceMethods.getPPGIrAmplitude`, returns `result as int`
  - `Future<int> getPPGRedAmplitude()` → invokes `DeviceMethods.getPPGRedAmplitude`, returns `result as int`
  - `Future<List<String>> getChannelNames()` → invokes `DeviceMethods.getChannelNames`, casts `result as List` then maps to `List<String>`
  - `Future<int> getChannelIndex(String channelName)` → invokes `DeviceMethods.getChannelIndexByName` with `{NeiryArgs.serial: serial, NeiryArgs.channelName: channelName}`, returns `result as int`
  - `Future<String> getChannelName(int index)` → invokes `DeviceMethods.getChannelNameByIndex` with `{NeiryArgs.serial: serial, NeiryArgs.index: index}`, returns `result as String`
  - `Future<int> getChannelsCount()` → invokes `DeviceMethods.getChannelsCount`, returns `result as int`

### Phase 3: Integration

- [x] **Task 5: Update DeviceLocator.createDevice() and barrel exports** (depends on Tasks 1-4)
  Files: `lib/src/api/device_locator.dart`, `lib/neiry_kit.dart`

  **`DeviceLocator.createDevice()`:**
  - Add `import '../api/device.dart'` (or adjust relative path) to `device_locator.dart`
  - Change return type from `Future<void>` to `Future<Device>`
  - After the `invokeMethod` call succeeds, return `Device(serial: serial)` instead of returning void
  - Remove the comment "A `Device` wrapper (future milestone) will be built on top of this."

  **Barrel export (`lib/neiry_kit.dart`):**
  Add these export lines (maintaining alphabetical order with existing exports):
  ```
  export 'src/api/device.dart';
  export 'src/models/eeg_artifact_data.dart';
  export 'src/models/eeg_data.dart';
  export 'src/models/psd_data.dart';
  export 'src/models/resistance_data.dart';
  ```

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add signal data models and Device class with lifecycle state machine"
- **Commit 2** (after tasks 3-5): "Add Device streams, query getters, and DeviceLocator integration"
