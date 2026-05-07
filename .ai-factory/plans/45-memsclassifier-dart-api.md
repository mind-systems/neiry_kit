# Plan: MEMSClassifier Dart API

## Context

Add the Dart-side MEMS classifier class following the established classifier pattern (CardioClassifier, EmotionsClassifier, etc.). This involves creating the classifier class, adding the `mems` channel constant, and exporting from the barrel file. The `MemsSample` model and `NeiryEvents.memsData` event channel ID already exist.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel constant

- [x] **Task 1: Add `mems` to `NeiryChannels`**
  Files: `lib/src/channel/channel_names.dart`
  Add `static const String mems = 'neiry_kit/mems';` to the `NeiryChannels` class, after the `cardio` entry (line 17). This is the MethodChannel ID the MEMSClassifier will use for `create`, `createCalibrated`, and `dispose` calls. `NeiryEvents.memsData` already exists on line 42 — do not add a duplicate.

### Phase 2: Classifier implementation

- [x] **Task 2: Create `MEMSClassifier` class** (depends on Task 1)
  Files: `lib/src/api/classifiers/mems_classifier.dart`
  Create the file following the `CardioClassifier` pattern (`lib/src/api/classifiers/cardio_classifier.dart`). Specifics:
  - Import `Device`, `channel_names.dart`, `MemsSample` from `../../models/mems_data.dart`, and `IndividualNfbData` from `../../models/individual_nfb_data.dart`.
  - `class MEMSClassifier` — non-static, owns native lifecycle.
  - `factory MEMSClassifier(Device device)` — check `device.isStarted`, throw `StateError('Cannot create MEMSClassifier before Device.start()')` if not started; delegate to private constructor with `calibration: null`.
  - `factory MEMSClassifier.withCalibration(Device device, IndividualNfbData data)` — same `isStarted` guard; delegate to private constructor with `calibration: data`.
  - `MEMSClassifier._(String serial, {IndividualNfbData? calibration})` — store `_serial`; fire async `_channel.invokeMethod<void>` for `ClassifierMethods.create` (plain) or `ClassifierMethods.createCalibrated` (with `NeiryArgs.calibrationData: calibration.toMap()`) capturing `_createError` on failure, exactly like `CardioClassifier._`.
  - `static const _channel = MethodChannel(NeiryChannels.mems)`.
  - `late final Stream<List<MemsSample>> _memsStream` — use `const EventChannel(NeiryEvents.memsData).receiveBroadcastStream({NeiryArgs.serial: _serial})` and map each event: cast raw to `List`, then `.map((e) => MemsSample.fromMap(e as Map<Object?, Object?>)).toList()`.
  - `Stream<List<MemsSample>> get memsStream` — guarded by `_checkNotDisposed()` and `_checkReady()`, returns `_memsStream`.
  - `_checkNotDisposed()` / `_checkReady()` — same pattern as other classifiers, using `'MEMSClassifier'` in error messages.
  - `Future<void> dispose()` — idempotent; set `_disposed = true`, await `_nativeReady`, skip if `_createError != null`, else invoke `ClassifierMethods.dispose` with `{NeiryArgs.serial: _serial}`.
  - Add doc comments matching the style of `CardioClassifier` (usage example, lifecycle section).

### Phase 3: Export

- [x] **Task 3: Export from barrel file** (depends on Task 2)
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/classifiers/mems_classifier.dart';` to the barrel file. Place it after the existing classifier exports (after `cardio_classifier.dart`, line 1) to keep alphabetical order among classifiers.
