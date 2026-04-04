# Plan: CardioClassifier

## Context

Add the Cardio classifier Dart API — the fifth and final classifier in the plugin. It wraps the native `clCCardio_*` C API, exposes two factory constructors (plain and with-calibration), and streams `CardioData`, raw PPG data, and a calibration-complete signal to consumers via EventChannels.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Models

- [x] **Task 1: Create CardioData model**
  Files: `lib/src/models/cardio_data.dart`
  Create an `@immutable` class `CardioData` mirroring `clCCardio_Data`. Fields:
  - `timestamp` (`DateTime`, required) — decoded from `map['ts']` as `DateTime.fromMillisecondsSinceEpoch`
  - `heartRate` (`double`, required) — decoded as `(map['heartRate'] as num).toDouble()`
  - `stressIndex` (`double`, required) — decoded as `(map['stressIndex'] as num).toDouble()`
  - `kaplanIndex` (`double`, required) — decoded as `(map['kaplanIndex'] as num).toDouble()`
  - `hasArtifacts` (`bool`, required) — cast directly from `map['hasArtifacts']`
  - `skinContact` (`bool`, required) — cast from `map['skinContact']`
  - `motionArtifacts` (`bool`, required) — cast from `map['motionArtifacts']`
  - `metricsAvailable` (`bool`, required) — cast from `map['metricsAvailable']`
  Include a `factory CardioData.fromMap(Map<Object?, Object?> map)` constructor. Follow the exact structure of `NfbUserState` — `const` constructor with named params, `@immutable` annotation. **Do not** use `orNull` from `sentinel.dart` for the float fields — the C struct `clCCardio_Data` initializes them to `0.F` (not the `-1.F` sentinel convention used by other classifiers), so `orNull` would never trigger. Instead, make all three floats non-nullable `double`. Add a doc comment on each float field stating that the value is only meaningful when `metricsAvailable` is `true`.

- [x] **Task 2: Create PpgData model**
  Files: `lib/src/models/ppg_data.dart`
  Create an `@immutable` class `PpgData` for raw PPG waveform batches from `clCPPGTimedData`. The native bridge iterates `clCPPGTimedData_GetCount/GetValue/GetTimestampMilli` and sends a map with the batch. Fields:
  - `values` (`List<double>`, required) — PPG sample values
  - `timestamps` (`List<int>`, required) — per-sample timestamps in milliseconds since epoch
  - `sampleCount` (`int`, required) — number of samples in this batch
  Include `factory PpgData.fromMap(Map<Object?, Object?> map)`. Decode `values` as `(map['values'] as List).map((v) => (v as num).toDouble()).toList()`, decode `timestamps` as `(map['timestamps'] as List).map((v) => (v as num).toInt()).toList()`, and `sampleCount` from `map['sampleCount'] as int`. Follow the batched-data pattern from `EegData` (list fields, no sentinel conversion needed for raw signal data).

### Phase 2: Classifier

- [x] **Task 3: Create CardioClassifier class** (depends on Tasks 1–2)
  Files: `lib/src/api/classifiers/cardio_classifier.dart`
  Create `CardioClassifier` following the `ProductivityClassifier` pattern exactly (it's the closest analog — two named factories with calibration). Structure:

  **Factories:**
  - `factory CardioClassifier(Device device)` — checks `device.isStarted`, throws `StateError` if not, delegates to `CardioClassifier._(device.serial, calibration: null)`
  - `factory CardioClassifier.withCalibration(Device device, IndividualNfbData nfbData)` — same guard, delegates with `calibration: nfbData`

  **Private constructor `._`:** fires `_channel.invokeMethod` with either `ClassifierMethods.create` or `ClassifierMethods.createCalibrated` depending on whether `calibration` is non-null, catches errors into `_createError`, stores future as `_nativeReady`. Pass `NeiryArgs.calibrationData: calibration.toMap()` for the calibrated path (same key as ProductivityClassifier).

  **Channel:** `static const _channel = MethodChannel(NeiryChannels.cardio)`

  **State:** `_serial`, `_nativeReady`, `_createError`, `_disposed` — identical pattern to ProductivityClassifier.

  **Cached streams (3):**
  - `_stateStream` → `_eventStream(EventChannel(NeiryEvents.cardioData), CardioData.fromMap)`
  - `_ppgStream` → `_eventStream(EventChannel(NeiryEvents.ppgData), PpgData.fromMap)`
  - `_calibratedStream` → wire to `EventChannel(NeiryEvents.cardioCalibratedEvent)`. This stream signals when the Cardio classifier's internal calibration completes (native `clCCardio_SetOnCalibratedEvent`). The C callback carries no data payload — use `receiveBroadcastStream({NeiryArgs.serial: _serial}).map((_) {})` directly (do not use `_eventStream` helper since the return type is `Stream<void>`). Consumers listen to know when calibration finishes and valid metrics begin.

  **No `errorStream`:** Unlike NFB, Emotions, and Productivity, the C API `CCardio.h` does not expose a `SetOnErrorEvent` callback. Do not add one — errors from Cardio surface as synchronous `clCError*` out-parameters, which the native bridge translates to `PlatformException` on the Dart side.

  **Guards:** `_checkNotDisposed()` / `_checkReady()` — same as all other classifiers.

  **`_eventStream<T>` helper:** same implementation as in other classifiers — `channel.receiveBroadcastStream({NeiryArgs.serial: _serial}).map(...)`.

  **Public stream getters:** `stateStream` (`Stream<CardioData>`), `ppgStream` (`Stream<PpgData>`), `calibratedStream` (`Stream<void>`) — each calls both guards then returns the cached stream.

  **`dispose()`:** idempotent; sets `_disposed = true`, awaits `_nativeReady`, skips native destroy if `_createError != null`, otherwise calls `ClassifierMethods.dispose` with `{NeiryArgs.serial: _serial}`.

  **Imports:** `dart:async`, `package:flutter/services.dart`, `../device.dart`, `../../channel/channel_names.dart`, `../../models/cardio_data.dart`, `../../models/ppg_data.dart`, `../../models/individual_nfb_data.dart`.

  **Doc comment:** mirror the ProductivityClassifier doc style — usage examples showing both factory paths and all three streams. Note that `calibratedStream` emits once when internal calibration completes, and that `CardioData` float fields are only valid when `metricsAvailable` is `true`.

### Phase 3: Barrel export

- [x] **Task 4: Update barrel exports** (depends on Tasks 1, 2, 3)
  Files: `lib/neiry_kit.dart`
  Add three export lines:
  - `export 'src/api/classifiers/cardio_classifier.dart';` — insert alphabetically among the classifier exports (before `emotions_classifier.dart`)
  - `export 'src/models/cardio_data.dart';` — insert alphabetically among the model exports (after `calibration_stage.dart`, before `device_info.dart`)
  - `export 'src/models/ppg_data.dart';` — insert alphabetically (after `physio_states.dart`, before `productivity_baselines.dart`)
