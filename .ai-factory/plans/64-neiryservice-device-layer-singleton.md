# Plan: NeiryService — device layer singleton

## Context

Introduces a single plain-Dart class (`example/lib/services/neiry_service.dart`) that owns the entire device + classifier lifecycle. Today every classifier is built lazily by its own Riverpod `NotifierProvider` that watches `activeDeviceProvider`, so MEMS/Cardio only get created when their tabs are first visited — pressing Start without visiting those tabs leaves them silent. The new service eagerly constructs all 6 classifiers at `connect()` and exposes their data via long-lived broadcast `StreamController`s, so subscribers attached before `connect()` receive everything once a device is online.

This milestone only creates the service. Riverpod wiring, screen migration, and provider deletion happen in later milestones (89–94 in `ROADMAP.md`). The existing providers and screens stay compiling and functional in parallel until those milestones land.

**Assumptions**

- `NfbCalibrator` in `lib/src/api/nfb_calibrator.dart` is declared `abstract final class` with only static methods and **no constructor at all** — Dart synthesises the default unnamed `NfbCalibrator()` which is non-const. To satisfy the milestone's `NfbCalibrator? get calibrator` contract while preserving the existing `abstract` modifier, two coordinated edits are required inside `lib/src/api/nfb_calibrator.dart`:
  1. Add an explicit `const NfbCalibrator();` constructor on the parent class — abstract classes may declare const constructors that are only invoked from concrete subclasses, and this does not change the public surface (no caller can construct `NfbCalibrator` directly because `final` blocks subtyping outside the library + `abstract` blocks direct instantiation).
  2. Introduce a private concrete subclass plus a public static sentinel:
     ```dart
     final class _NfbCalibratorHandle extends NfbCalibrator {
       const _NfbCalibratorHandle();
     }
     // inside abstract final class NfbCalibrator { … }:
     const NfbCalibrator();
     static const NfbCalibrator handle = _NfbCalibratorHandle();
     ```
  Without step 1, `const _NfbCalibratorHandle()` fails with `The constructor 'NfbCalibrator' isn't a const constructor.` because a const generative constructor in a subclass must invoke a const constructor in the superclass. The `handle` constant becomes the sentinel `NeiryService` stores while connected.

  **Fallback A** (if the const constructor edit on `NfbCalibrator` is rejected): drop `const` from the sentinel — `static final NfbCalibrator handle = _NfbCalibratorHandle();` plus `_NfbCalibratorHandle()` (no `const`). Works without touching `NfbCalibrator`'s constructor.

  **Fallback B** (if any SDK touch is rejected): drop the `NfbCalibrator? get calibrator` getter from this milestone's public surface, ship `bool get hasCalibrator => isConnected;` instead, remove the `_calibrator` field, and defer the full getter contract to milestone 94. Record the deviation in `.ai-factory/notes/` if this path is taken.
- `StreamController<T>.broadcast()` is used for the long-lived multiplexer streams — the default constructor already delivers asynchronously, no `sync:` flag is needed. Each controller is opened once in the constructor and never closed until `dispose()` — this is what makes "subscribe before connect, receive after connect" work.
- All classifier `dispose()` calls cancel internal native subscriptions but do not close the multiplexer controllers — the controllers stay open so the next `connect()` can re-feed them.
- Double-subscribing to a `Device` stream (once internally by `Device._startStateTracking()` for cached-state maintenance, once by `NeiryService` for fan-in) is safe: `Device` exposes its event-channel streams as cached `late final` broadcast streams, so Flutter multiplexes both listeners onto a single native subscription. The "Concurrent subscription warning" on `Device` refers to multiple `Device` *instances*, not multiple listeners on one instance. Note: `Device._modeChangedStream` is not a direct cached stream but an inline `.map().where().cast()` chain over the cached event-channel stream — `.map`/`.where`/`.cast` preserve broadcast-ness in Dart (the resulting stream's `isBroadcast` mirrors the source), so adding a second listener stays safe.
- `isConnected` and `isStarted` derive their truth from the underlying `Device` (`_device?.isConnected ?? false`, `_device?.isStarted ?? false`); `NeiryService` does not need to cache these flags separately. After `Device.stop()` completes successfully, `Device._started` flips to `false` internally and the getter behaves correctly.
- `_connecting` is owned exclusively by `connect()`'s try/finally — `disconnect()` and `dispose()` never read or write it. This is intentional insurance against future refactors that might schedule a fire-and-forget cleanup calling `disconnect()` mid-connect.

## Settings

- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Skeleton, scan, lifecycle

- [x] **Task 1: Create service file with constructor and disposal scaffolding**
  Files: `example/lib/services/neiry_service.dart`
  Create `class NeiryService` with no Flutter/Riverpod imports — only `dart:async`, `package:neiry_kit/neiry_kit.dart`. Constructor stores `final DeviceLocator _locator = DeviceLocator();` plus eagerly initialises every broadcast multiplexer `StreamController` (one per stream listed in Task 5) as a private `final` field — e.g. `final _eegController = StreamController<EegData>.broadcast();` (no `sync:` argument — default async delivery). Add private mutable state:
  - `Device? _device;`
  - `bool _disposed = false;`
  - `bool _connecting = false;` (re-entry guard for Task 3 — owned exclusively by `connect()`)
  - Six classifier nullable fields: `NfbClassifier? _nfb;`, `PhysioClassifier? _physio;`, `EmotionsClassifier? _emotions;`, `ProductivityClassifier? _productivity;`, `CardioClassifier? _cardio;`, `MEMSClassifier? _mems;`
  - `IndividualNfbData? _nfbData;`
  - `NfbCalibrator? _calibrator;` (required by Task 3 step 7 and Task 4 reset — see Assumptions for sentinel approach)
  - `final List<StreamSubscription<dynamic>> _activeSubscriptions = [];` for fan-in subscriptions cancelled on disconnect.

  Add a private `_checkNotDisposed()` guard that throws `StateError('NeiryService has been disposed')`. Note: `_checkNotDisposed()` is called at the top of `scan()`, `connect()`, `start()`, but **not** at the top of `disconnect()` or `stop()` — both are no-ops when there is no device, and `dispose()` awaits `disconnect()` after flipping `_disposed = true`, so a `_checkNotDisposed()` in `disconnect()` would deadlock the disposal path. Add basic state getters: `bool get isConnected => _device?.isConnected ?? false;` and `bool get isStarted => _device?.isStarted ?? false;`. Do NOT touch any existing files yet.

- [x] **Task 2: Implement `scan` and `dispose`** (depends on Task 1)
  Files: `example/lib/services/neiry_service.dart`
  Add `Stream<List<DeviceInfo>> scan({NeiryDeviceType type = NeiryDeviceType.any, int searchTime = 5})` — single line: `_checkNotDisposed(); return _locator.requestDevices(type: type, searchTime: searchTime);`. Add `Future<void> dispose()` with this exact shape:
  ```dart
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _locator.dispose();
    await _eegController.close();
    // … close every multiplexer controller in turn …
  }
  ```
  The single `if (_disposed) return;` check at the top is the entire re-entry guard — there is only one `_disposed` flag, used both as the dispose-once latch and as the "service unusable" marker checked by `_checkNotDisposed()`. Closing controllers after `disconnect()` lets consumers see clean stream termination.

### Phase 2: Connect, classifiers, and stream fan-in

- [x] **Task 3: Implement `connect()` — create device and all six classifiers, wire stream fan-in** (depends on Task 2)
  Files: `example/lib/services/neiry_service.dart`
  Signature: `Future<void> connect(String serial, {bool bipolarChannels = false, IndividualNfbData? nfbData}) async`. Steps in order:
  1. `_checkNotDisposed();` then `if (_connecting) throw StateError('Connect already in flight');` then `if (isConnected) throw StateError('Already connected — call disconnect() first');`. Set `_connecting = true;` and wrap the remainder in `try { … } finally { _connecting = false; }` so re-entry is reliably gated between `createDevice` and the end of `device.connect()`.
  2. Store `_nfbData = nfbData;`.
  3. `_device = await _locator.createDevice(serial);`.
  4. `try { await _device!.connect(bipolarChannels: bipolarChannels); } catch (e) { try { await _device!.dispose(); } catch (_) {} _device = null; _nfbData = null; rethrow; }` — mirror the cleanup pattern in `active_device_provider.dart:createAndConnect()`. (`_calibrator` is not touched here — it is only assigned in step 7 and is guaranteed null at this point.)
  5. Construct classifiers as private fields — eager, no lazy init:
     ```
     _nfb = NfbClassifier(_device!, calibration: nfbData);
     _physio = PhysioClassifier(_device!);
     _emotions = EmotionsClassifier(_device!);
     _productivity = nfbData != null
         ? _safeProductivityWithCalibration(_device!, nfbData)
         : ProductivityClassifier(_device!);
     _cardio = nfbData != null
         ? CardioClassifier.withCalibration(_device!, nfbData)
         : CardioClassifier(_device!);
     _mems = nfbData != null
         ? MEMSClassifier.withCalibration(_device!, nfbData)
         : MEMSClassifier(_device!);
     ```
     `_safeProductivityWithCalibration` is a private instance helper — copy the pattern from `example/lib/providers/productivity_classifier_provider.dart:45-58`:
     ```dart
     ProductivityClassifier _safeProductivityWithCalibration(
       Device device,
       IndividualNfbData data,
     ) {
       try {
         return ProductivityClassifier.withCalibration(device, data);
       } on UnsupportedError {
         return ProductivityClassifier(device);
       }
     }
     ```
  6. Set `_calibrator = NfbCalibrator.handle;` using the sentinel introduced in `lib/src/api/nfb_calibrator.dart` (see Assumptions for the SDK-side definition). Done **before** step 7 so the `_calibrator = null` cleanup in any future failure path inside step 7 would have a real value to clear.
  7. Subscribe each underlying device/classifier stream and forward into the matching multiplexer controller — store every subscription in `_activeSubscriptions`. Example: `_activeSubscriptions.add(_device!.eegStream.listen(_eegController.add, onError: _eegController.addError));`. Wire all 13 streams listed in Task 5.

     Note: `Device` already subscribes internally to `connectionStateStream`, `modeChangedStream`, and `batteryStream` to maintain its cached state. Adding NeiryService's listeners on top is safe — those streams are cached broadcast streams (`late final` in `Device`), and Flutter multiplexes both listeners onto a single native event-channel subscription. `_modeChangedStream` uses an inline `.map().where().cast()` chain but those operators preserve broadcast-ness, so the second listener stays valid.

- [x] **Task 4: Implement `disconnect()`, `start()`, `stop()`** (depends on Task 3)
  Files: `example/lib/services/neiry_service.dart`
  `disconnect()`: no-op when `_device == null`. Otherwise follow this order — classifiers tear down **before** the device, mirroring how Riverpod tears down dependent providers before `active_device_provider.disconnectAndDispose()` runs today:
  1. Cancel `_activeSubscriptions`: `for (final s in _activeSubscriptions) { try { await s.cancel(); } catch (_) {} } _activeSubscriptions.clear();`.
  2. Dispose every classifier concurrently — disposing in parallel avoids serialising six native round-trips on the platform thread:
     ```dart
     await Future.wait<void>([
       if (_nfb != null) _nfb!.dispose().catchError((_) {}),
       if (_physio != null) _physio!.dispose().catchError((_) {}),
       if (_emotions != null) _emotions!.dispose().catchError((_) {}),
       if (_productivity != null) _productivity!.dispose().catchError((_) {}),
       if (_cardio != null) _cardio!.dispose().catchError((_) {}),
       if (_mems != null) _mems!.dispose().catchError((_) {}),
     ]);
     _nfb = null; _physio = null; _emotions = null;
     _productivity = null; _cardio = null; _mems = null;
     ```
  3. Tear down the device, guarding each step: `if (_device!.isStarted) { try { await _device!.stop(); } catch (_) {} }` then `try { await _device!.disconnect(); } catch (_) {}` then `try { await _device!.dispose(); } catch (_) {}` — pattern from milestone 82's fix in `active_device_provider.dart:disconnectAndDispose()`.
  4. Reset device-scoped fields: `_device = null; _nfbData = null; _calibrator = null;`.

  Multiplexer controllers stay open.

  `start()`: `_checkNotDisposed(); if (_device == null) throw StateError('Not connected'); await _device!.start();` — errors propagate to the caller (no try/catch).

  `stop()`: `_checkNotDisposed(); if (_device == null) return; await _device!.stop();` — return type `Future<void>`; errors **propagate** to the caller (no try/catch), so a UI Start button can surface "stop failed". Callers in milestone 92 read `device.isStarted` via NeiryService getter; they do not consume the bool return of `Device.stop`.

### Phase 3: Public surface

- [x] **Task 5: Expose data stream getters** (depends on Task 3)
  Files: `example/lib/services/neiry_service.dart`
  Add public broadcast `Stream<T> get <name> => _<name>Controller.stream;` for each of the 13 streams: `connectionStateStream` (`Stream<NeiryConnectionState>`), `modeStream` (`Stream<NeiryDeviceMode>`), `eegStream` (`Stream<EegData>`), `psdStream` (`Stream<PsdData>`), `resistanceStream` (`Stream<ResistanceData>`), `batteryStream` (`Stream<int>`), `physioStream` (`Stream<PhysiologicalStatesValue>` from `_physio.stateStream`), `emotionsStream` (`Stream<EmotionsStates>`), `cardioStream` (`Stream<CardioData>`), `memsStream` (`Stream<List<MemsSample>>` — unthrottled here; throttling stays in the consumer provider as `memsProvider` does today, and will move to the future provider/consumer wrapping `NeiryService` in milestones 89–94), `nfbStream` (`Stream<NfbUserState>`), `productivityIndexesStream` (`Stream<ProductivityIndexes>`), `productivityMetricsStream` (`Stream<ProductivityMetrics>`). All emit nothing when the corresponding classifier is null — naturally handled because the fan-in subscription only exists between `connect()` and `disconnect()`. A subscriber attached *before* `connect()` will only see events that arrive after `_activeSubscriptions.add(...)` runs (intended behavior — micro-gap is negligible because classifiers emit only after `start()`). Do not add `artifactsStream`, `physioCalibrationProgressStream`, `productivityCalibrationProgressStream`, `physioCalibratedStream`, `productivityCalibratedStream`, `productivityBaselinesStream`, `cardioPpgStream`, `cardioCalibratedStream` in this milestone — they are added incrementally in milestones 89–90.

- [x] **Task 6: Expose classifier accessors and calibrator + add SDK sentinel** (depends on Task 3)
  Files: `example/lib/services/neiry_service.dart`, `lib/src/api/nfb_calibrator.dart`
  In `lib/src/api/nfb_calibrator.dart`, make **two coordinated edits** to the existing `abstract final class NfbCalibrator`:
  1. Add a const default constructor on the parent class so a const subclass can extend it: `const NfbCalibrator();`. Required because `NfbCalibrator` currently declares no constructor, so Dart synthesises a non-const default constructor, and a const subclass constructor cannot invoke a non-const super.
  2. Add a private concrete subclass and a public static sentinel constant:
  ```dart
  abstract final class NfbCalibrator {
    const NfbCalibrator();
    static const NfbCalibrator handle = _NfbCalibratorHandle();
    // … existing static members unchanged …
  }

  final class _NfbCalibratorHandle extends NfbCalibrator {
    const _NfbCalibratorHandle();
  }
  ```
  Verify the symbol is re-exported via the existing barrel — `NfbCalibrator` is already exported, so the `handle` static is reachable from `example/` consumers without any new export line.

  In `example/lib/services/neiry_service.dart`, expose ONLY the two classifier getters the milestone authorises: `PhysioClassifier? get physioClassifier => _physio;` and `ProductivityClassifier? get productivityClassifier => _productivity;`. Do NOT add getters for the other four — they are accessed via streams. Add `NfbCalibrator? get calibrator => _calibrator;`. `_calibrator` is set in `connect()` step 6 to `NfbCalibrator.handle` and reset to `null` in `disconnect()`/`dispose()`. Do NOT add `setMemsCalibration()`, `setProductivityCalibration()`, or any other runtime reconfiguration method — `nfbData` is passed once into `connect()` and is otherwise immutable for the lifetime of the connection.

  Fallback path: if the SDK touch is rejected during implementation, choose one of the Assumptions fallbacks — Fallback A (drop `const` from the sentinel, avoid the parent-constructor edit) or Fallback B (drop the getter entirely, expose `bool get hasCalibrator => isConnected;`, remove the `_calibrator` field, and record the deviation in `.ai-factory/notes/` so milestone 94 owns the follow-up).

### Phase 4: Sanity check

- [x] **Task 7: Verify the service compiles in isolation** (depends on Tasks 1–6)
  Files: none (no edits — just verification)
  From `neiry_kit/example/`, run `dart analyze lib/services/neiry_service.dart`. `dart analyze` honors path arguments and scopes findings to the named file, unlike `flutter analyze` which can include diagnostics from the rest of the package. Expect zero errors in the file. Some legacy lints elsewhere in `example/` are out of scope. The file must have no imports from `package:flutter/...` or `package:flutter_riverpod/...` — verify by grep. Additionally run `dart analyze lib/src/api/nfb_calibrator.dart` from `neiry_kit/` to confirm the SDK-side edit (const constructor + sentinel) compiles. Success criterion: zero new errors introduced in either file; existing example-app warnings unchanged.

## Commit Plan

- **Commit 1** (after tasks 1–2): "Scaffold NeiryService with scan and dispose"
- **Commit 2** (after tasks 3–4): "Wire NeiryService connect/disconnect lifecycle and classifier construction"
- **Commit 3** (after tasks 5–7): "Expose NeiryService data streams, classifier getters, and calibrator sentinel" — touches **two files**: `lib/src/api/nfb_calibrator.dart` (SDK-side const constructor + `_NfbCalibratorHandle` + `handle` sentinel) and `example/lib/services/neiry_service.dart` (stream getters, classifier getters, `calibrator` getter). Keep both files in the same commit so the sentinel introduction and its first consumer land together — splitting them would leave one commit with a defined-but-unused symbol.
