# Plan: Dart channel contract

## Context
Define the entire platform channel contract as Dart constants and enums, so both the Dart API layer and native bridges share one source of truth for all channel IDs, method names, argument keys, and enum int mappings.

Note: the roadmap milestone description says `lib/src/channel_names.dart` (flat in `src/`), but ARCHITECTURE.md specifies a `channel/` subdirectory. This plan follows ARCHITECTURE.md as the authoritative source — the file goes to `lib/src/channel/channel_names.dart`. The roadmap also says "28 EventChannels" but the spec note enumerates exactly 26; this plan matches the spec (26).

## Settings
- Testing: yes (milestone explicitly requires unit tests)
- Logging: none
- Docs: no

## Tasks

### Phase 1: Channel constants

- [x] **Task 1: Create `lib/src/channel/channel_names.dart` with MethodChannel and EventChannel IDs**
  Files: `lib/src/channel/channel_names.dart`
  Create the file with two `abstract final class` containers:
  - `NeiryChannels` — 8 static `const String` fields for MethodChannel IDs: `deviceLocator` (`'neiry_kit/device_locator'`), `device` (`'neiry_kit/device'`), `nfb` (`'neiry_kit/nfb'`), `physiological` (`'neiry_kit/physiological'`), `emotions` (`'neiry_kit/emotions'`), `productivity` (`'neiry_kit/productivity'`), `cardio` (`'neiry_kit/cardio'`), `nfbCalibrator` (`'neiry_kit/nfb_calibrator'`).
  - `NeiryEvents` — 26 static `const String` fields for EventChannel IDs (count matches the spec note exactly): `deviceList` (`'neiry_kit/events/deviceList'`), `eeg`, `psd`, `eegArtifacts`, `resistance`, `battery`, `connectionStatus`, `modeSwitched`, `nfbState`, `physiologicalState`, `emotionsState`, `productivityMetrics`, `productivityIndexes`, `cardioData`, `ppgData`, `memsData`, `nfbCalibration`, `physiologicalCalibrationProgress`, `physiologicalCalibrated`, `productivityCalibrationProgress`, `productivityCalibrated`, `cardioCalibratedEvent`, `error`, `nfbError`, `emotionsError`, `productivityError`. All prefixed with `'neiry_kit/events/'`. Note: `cardioCalibratedEvent` is included per spec but the exact native callback name needs confirmation from `_c_cardio_8h` when implementing the iOS/Android bridges — for now the string constant is defined.

- [x] **Task 2: Add method name string classes**
  Files: `lib/src/channel/channel_names.dart`
  Append four `abstract final class` containers to the same file:
  - `DeviceLocatorMethods` — `requestDevices`, `setSingleThreaded`, `setLogLevel`, `getVersionString`.
  - `DeviceMethods` — `createDevice`, `connect`, `disconnect`, `start`, `stop`, `getMode`, `isConnected`, `getBatteryCharge`, `getInfo`, `getEEGSampleRate`, `getPPGSampleRate`, `getMEMSSampleRate`, `getPPGIrAmplitude`, `getPPGRedAmplitude`, `getChannelNames`, `getChannelIndexByName`, `getChannelNameByIndex`, `getChannelsCount`.
  - `ClassifierMethods` — `create`, `createCalibrated`, `startBaselineCalibration`, `stopBaselineCalibration`, `importBaselines`, `resetAccumulatedFatigue`.
  - `NFBCalibratorMethods` — `startCalibration`, `stopCalibration`, `importCalibration`, `getCalibration`, `isCalibrated`.
  Each field is a `static const String` whose value equals the camelCase name (e.g. `static const String requestDevices = 'requestDevices';`).

- [x] **Task 3: Add argument key strings class**
  Files: `lib/src/channel/channel_names.dart`
  Append `abstract final class NeiryArgs` with 11 static `const String` fields: `serial`, `deviceType`, `searchTime`, `mode`, `level`, `enabled`, `baselines`, `calibrationData`, `calibratorData`, `channelName`, `index`.

### Phase 2: Enums

- [x] **Task 4: Add enums with int mappings in a separate file**
  Files: `lib/src/channel/enums.dart`
  Create a new file with three enums, separate from the string constants in `channel_names.dart` — enums are richer data types with factories, not channel contract strings:
  - `NeiryDeviceType` — values with explicit SDK int codes: `headband(0)`, `buds(1)`, `headphones(2)`, `impulse(3)`, `any(4)`, `brainBit(6)`, `sinWave(100)`, `noise(101)`. Use the enhanced enum syntax: `enum NeiryDeviceType { headband(0), ... ; const NeiryDeviceType(this.code); final int code; }`. Add a `static NeiryDeviceType fromCode(int code)` factory that throws `ArgumentError` with a descriptive message including the invalid code value (e.g. `'Unknown NeiryDeviceType code: $code'`).
  - `NeiryDeviceMode` — `resistance(0)`, `signal(1)`, `signalAndResist(2)`, `startMEMS(3)`, `stopMEMS(4)`, `startPPG(5)`, `stopPPG(6)`. Same enhanced enum pattern with `code` field and `fromCode`. Note: the spec note flagged Start/StopPPG indices as uncertain, but the SDK header `CDevice.h` confirms `StartPPG=5, StopPPG=6` — this is resolved, use these values.
  - `NeiryConnectionState` — `disconnected(0)`, `connected(1)`, `unsupportedConnection(2)`. Same pattern.
  All `fromCode` factories must include the rejected code value in the `ArgumentError` message for debuggability when a native bridge sends an unexpected int.

### Phase 3: Export and cleanup

- [x] **Task 5: Export from barrel file and delete scaffolding tests**
  Files: `lib/neiry_kit.dart`, `test/neiry_kit_test.dart`, `test/neiry_kit_method_channel_test.dart`
  Replace the current contents of `lib/neiry_kit.dart` with a barrel that exports the channel contract:
  ```dart
  export 'src/channel/channel_names.dart';
  export 'src/channel/enums.dart';
  ```
  Remove the old `NeiryKit` class and its import of `neiry_kit_platform_interface.dart` — that scaffolding served its purpose and will be replaced as the real API develops. Keep `neiry_kit_platform_interface.dart` and `neiry_kit_method_channel.dart` on disk (other milestones may reference them), but they are no longer re-exported.
  Delete `test/neiry_kit_test.dart` and `test/neiry_kit_method_channel_test.dart` — both are scaffolding tests for the removed `NeiryKit` / `getPlatformVersion` flow and will fail to compile after the barrel change (the `NeiryKit` class they import no longer exists). The new test in Task 6 replaces them.

### Phase 4: Tests

- [x] **Task 6: Add unit tests for string uniqueness and enum int mappings**
  Files: `test/channel_names_test.dart`
  Create a new test file that imports `package:neiry_kit/neiry_kit.dart` and verifies:
  1. **All MethodChannel IDs are unique** — collect all `NeiryChannels` values into a `List<String>`, assert `length == Set.from(list).length`.
  2. **All EventChannel IDs are unique** — same for `NeiryEvents`.
  3. **No overlap between MethodChannel and EventChannel IDs** — intersection of the two sets is empty.
  4. **All method name strings are unique within each class** — collect values from `DeviceLocatorMethods`, `DeviceMethods`, `ClassifierMethods`, `NFBCalibratorMethods` individually and assert uniqueness.
  5. **All argument key strings are unique** — same for `NeiryArgs`.
  6. **`NeiryDeviceType` int codes match SDK** — assert `NeiryDeviceType.headband.code == 0`, `buds.code == 1`, `headphones.code == 2`, `impulse.code == 3`, `any.code == 4`, `brainBit.code == 6`, `sinWave.code == 100`, `noise.code == 101`.
  7. **`NeiryDeviceMode` int codes match SDK** — assert each value's `code` matches its expected int.
  8. **`NeiryConnectionState` int codes match SDK** — assert `disconnected.code == 0`, `connected.code == 1`, `unsupportedConnection.code == 2`.
  9. **`fromCode` round-trips** — for each enum, verify `fromCode(value.code) == value` for every value.
  10. **`fromCode` throws on unknown code** — assert `throwsArgumentError` for an invalid int (e.g. `999`).
  Use `flutter_test` only (no extra dependencies). Since all constants are pure Dart with no platform dependency, tests run with `flutter test` without mocking.
  Note: Dart has no runtime reflection in Flutter, so the test must manually enumerate every constant in `List<String>` collections. Add a comment at the top of the test file: `// When adding new constants to channel_names.dart or enums.dart, add them to the corresponding list here.` This ensures the uniqueness check stays in sync as the contract grows.

## Commit Plan
- **Commit 1** (after tasks 1-5): "Add Dart channel contract with all channel IDs, method names, argument keys, and enums"
- **Commit 2** (after task 6): "Add unit tests for channel contract uniqueness and enum int mappings"
