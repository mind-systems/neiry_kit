# Plan: Export + integration tests

## Context

Verify that all Dart API classes are exported from the barrel file and add integration tests covering Device state machine guards, classifier factory guards, stream return types, and CalibrationEvent sealed dispatch exhaustiveness.

## Settings
- Testing: yes (this milestone IS tests)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Export verification + fix existing test gaps

- [x] **Task 1: Verify barrel file exports all public classes**
  Files: `lib/neiry_kit.dart`
  Compare every `.dart` file under `lib/src/` (excluding `models/internal/sentinel.dart`, which is intentionally internal) against the barrel file `lib/neiry_kit.dart`. Currently all 30 public source files are exported — confirm this is still the case at implementation time. If any file is missing, add its export line. This satisfies the milestone requirement "export all classes".

- [x] **Task 2: Fix channel_names_test.dart — add missing IDs and method** (depends on Task 1)
  Files: `test/channel_names_test.dart`
  The `NeiryEvents` uniqueness list and "No overlap" set are both missing three EventChannel IDs added after the test was written: `NeiryEvents.physiologicalIndividualNfb`, `NeiryEvents.productivityBaselines`, `NeiryEvents.productivityIndividualNfb`. Add all three to both the `ids` list in the `'NeiryEvents — EventChannel IDs are unique'` group and the `eventIds` set in the `'No overlap between MethodChannel and EventChannel IDs'` group. Update the count assertion: count every static `String` constant in the `NeiryEvents` class in `channel_names.dart` and set the expected value to that number (currently 29 — verify against source before hardcoding).
  Also add `ClassifierMethods.dispose` to the `'ClassifierMethods — unique'` group's `names` list — it was defined in `channel_names.dart` but omitted from the test.

### Phase 2: Integration tests

- [x] **Task 3: Device state machine guard tests** (depends on Task 2)
  Files: `test/api_test.dart` (new file)
  Create `test/api_test.dart` importing `package:neiry_kit/neiry_kit.dart` and `package:flutter_test/flutter_test.dart`. Follow the same flat structure as `models_test.dart` (flat `group`/`test`, `// ──…──` section dividers, no `setUp`).

  Add a group `'Device state machine — wrong-order throws'` with these tests:
  - `start() before connect() → throws DeviceNotConnectedException` — create `Device(serial: 'test')`, call `device.start()`, expect it `throwsA(isA<DeviceNotConnectedException>())`. The `_checkConnected()` guard fires synchronously before any MethodChannel call, so no mock needed.
  - `getInfo() before connect() → throws DeviceNotConnectedException` — same pattern with `device.getInfo()`.
  - `getEEGSampleRate() before connect() → throws DeviceNotConnectedException` — same pattern, confirms all async getters are guarded.
  - `connect() when already connected → throws StateError` — this test requires mocking both the MethodChannel AND three EventChannels because `connect()` calls `_startStateTracking()`, which subscribes (`.listen()`) to `_connectionStateStream`, `_modeChangedStream`, and `_batteryStream`. Without mock handlers the `listen` call triggers `MissingPluginException`.
    Set up: (a) `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` for `MethodChannel(NeiryChannels.device)` returning `null` for all calls. (b) For each of `NeiryEvents.connectionStatus`, `NeiryEvents.modeSwitched`, `NeiryEvents.battery`: call `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('<channel_id>', (message) async => const StandardMethodCodec().encodeSuccessEnvelope(null))` so the `listen` platform message succeeds silently.
    Call `await device.connect()` (succeeds — first connect sets `_connected = true` and subscribes to EventChannels). Call `device.connect()` again, expect `throwsA(isA<StateError>())` with message containing `'already connected'`.
    In a `tearDown` (or at the end of the test), clear all mock handlers by passing `null`.
  - `methods after dispose() → throws StateError` — create a **fresh** `Device(serial: 'test')`. Do NOT call `connect()` first. Call `await device.dispose()` (which only invokes `DeviceMethods.disconnect` on the MethodChannel — set up the same MethodChannel mock returning `null`). After dispose, verify: `expect(() => device.connect(), throwsA(isA<StateError>()))` (async — throws sync from `_checkNotDisposed` before awaiting), `expect(() => device.start(), throwsA(isA<StateError>()))`, `expect(() => device.eegStream, throwsA(isA<StateError>()))` (sync closure wrapping the getter — the getter calls `_checkNotDisposed()` synchronously, so `expect(() => device.eegStream, ...)` is correct; do NOT write `expect(device.eegStream, ...)` which would throw before `expect` runs), and `expect(() => device.getInfo(), throwsA(isA<StateError>()))`. No EventChannel mocking needed since `connect()` was never called.

  Add a group `'Device — initial state'` with tests:
  - `isConnected is false` — `expect(Device(serial: 'x').isConnected, isFalse)`.
  - `isStarted is false` — same with `isStarted`.
  - `isValid is true` — same with `isValid`.
  - `battery is null` — same with `battery`.
  - `mode is null` — same with `mode`.
  - `connectionState is disconnected` — `expect(device.connectionState, NeiryConnectionState.disconnected)`.

- [x] **Task 4: Classifier factory guards + stream type assertions** (depends on Task 3)
  Files: `test/api_test.dart`

  Add a group `'Classifier factories — throw when device not started'` with one test per factory path (7 total):
  - `NfbClassifier(device) → throws StateError` — `final device = Device(serial: 'test');` then `expect(() => NfbClassifier(device), throwsA(isA<StateError>()))`. The factory checks `device.isStarted` synchronously, no mock needed.
  - `PhysioClassifier(device) → throws StateError`
  - `EmotionsClassifier(device) → throws StateError`
  - `ProductivityClassifier(device) → throws StateError`
  - `ProductivityClassifier.withCalibration(device, data) → throws StateError` — use `const IndividualNfbData()` for the `data` argument. The guard throws before the data parameter is ever used, so the default constructor (which has sensible defaults for all fields) is sufficient and simpler than `fromMap(...)`.
  - `CardioClassifier(device) → throws StateError`
  - `CardioClassifier.withCalibration(device, data) → throws StateError` — same: use `const IndividualNfbData()`.
  All error messages must contain `'before Device.start()'`.

  Add a group `'Device streams — return types match models'` with one test per stream (8 total):
  - `eegStream is Stream<EegData>` — `expect(device.eegStream, isA<Stream<EegData>>())`. This works because `receiveBroadcastStream()` does NOT send a platform message on creation — it defers to `onListen`. So accessing the `late final` getter is safe without mocking. The `.map(decode)` wrapper preserves the generic type.
  - `psdStream is Stream<PsdData>`
  - `artifactsStream is Stream<EegArtifactData>`
  - `resistanceStream is Stream<ResistanceData>`
  - `batteryStream is Stream<int>`
  - `errorStream is Stream<String>`
  - `connectionStateStream is Stream<NeiryConnectionState>`
  - `modeChangedStream is Stream<NeiryDeviceMode>`

- [x] **Task 5: CalibrationEvent sealed dispatch — exhaustive switch** (depends on Task 3)
  Files: `test/api_test.dart`

  Add a group `'CalibrationEvent — sealed dispatch is exhaustive'` with:
  - `switch covers all subtypes` — construct both subtypes (`CalibrationStageFinished(stage: CalibrationStage.stage1)` and `CalibrationCompleted(data: const IndividualNfbData())`), iterate over them, and use an exhaustive `switch` expression with destructuring patterns (`case CalibrationStageFinished(:final stage)` / `case CalibrationCompleted(:final data)`) to produce a label string. Verify each label is non-empty. This test is a compile-time sentinel: if a new sealed subtype is added without updating the switch, the test fails to compile.
  - `CalibrationStageFinished carries correct stage` — construct with `stage3`, verify `event.stage == CalibrationStage.stage3`.
  - `CalibrationCompleted carries correct data` — construct with `const IndividualNfbData(individualFrequency: 11.5)`, verify `event.data.individualFrequency == 11.5`.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add missing channel IDs to tests and verify barrel exports"
- **Commit 2** (after tasks 3-5): "Add Device, classifier, and CalibrationEvent integration tests"
