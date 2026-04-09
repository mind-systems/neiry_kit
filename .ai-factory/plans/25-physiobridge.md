# Plan: PhysioBridge

## Context

Implement the iOS native bridge (`PhysioBridge.swift`) for the `clCPhysiologicalStates` classifier and wire it into the plugin, replacing the current stub handlers with a live implementation that forwards all 4 SDK callbacks to Dart via EventChannels.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: iOS Bridge Implementation

- [x] **Task 1: Create PhysioBridge.swift**
  Files: `ios/Classes/classifiers/PhysioBridge.swift`
  Create the full bridge class following the same structure as `NfbBridge.swift` and `EmotionsBridge.swift`:

  **Scaffold:**
  - `private static weak var activeBridge: PhysioBridge?` for C callback access.
  - `private var physio: OpaquePointer?` to hold the `clCPhysiologicalStates` handle.
  - Four `DeviceStreamHandler` instances:
    - `physiologicalStateHandler` → `"neiry_kit/events/physiologicalState"`
    - `calibrationProgressHandler` → `"neiry_kit/events/physiologicalCalibrationProgress"`
    - `calibratedHandler` → `"neiry_kit/events/physiologicalCalibrated"`
    - `individualNfbHandler` → `"neiry_kit/events/physiologicalIndividualNfb"`
  - `allStreamHandlers()` returning all 4 pairs.

  **`create(device:)`** — call `clCPhysiologicalStates_Create(device, &error)`, wrap with `try checkCError(error)`, then `try registerCallbacks()`. If `physio` is already non-nil, call `unregisterCallbacks()` first (same pattern as `NfbBridge.create`).

  **`registerCallbacks()`** — mark as `private func registerCallbacks() throws`. Register all 4 SDK callbacks. Key difference from `NfbBridge`/`EmotionsBridge`: every `clCPhysiologicalStates_SetOn*Event` takes **3 parameters** `(handle, handler, &error)` instead of 2. This means:
  1. **No trailing closure syntax** — the `&error` argument comes after the closure, so the closure must be passed as a labeled argument (or inline before the error arg). Do NOT copy the trailing-closure style from `EmotionsBridge`/`NfbBridge` — it will not compile.
  2. **Error checking at the registration call site** — declare a `var error = clCError()` before each registration call, pass `&error` as the third argument, then call `try checkCError(error)` after. The `clCError*` belongs to the registration function, not to the callback handler. The callback closures themselves have no error parameter.

  Example pattern for each registration:
  ```swift
  var error1 = clCError()
  clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, { _, data in
      guard let bridge = PhysioBridge.activeBridge,
            let data = data else { return }
      // ... serialize and send ...
  }, &error1)
  try checkCError(error1)
  ```

  The 4 callbacks to register:
  - `clCPhysiologicalStates_SetOnStatesUpdateEvent` — serialize `clCPhysiologicalStates_Value` pointee to map with all 8 fields: `ts` (Int64), `relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress` (all Float), `nfbArtifacts`, `cardioArtifacts` (both Bool). Send via `physiologicalStateHandler.send(map)`.
  - `clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent` — callback receives `(handle, Float progress)`. Clamp to `max(0.0, min(1.0, progress))` before emitting `["progress": clampedValue]` via `calibrationProgressHandler.send(map)`.
  - `clCPhysiologicalStates_SetOnCalibratedEvent` — callback receives `(handle, const clCPhysiologicalStates_Baselines*)`. Serialize all 6 fields to map: `ts` (Int64), `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration` (all Float). Send via `calibratedHandler.send(map)`.
  - `clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent` — callback receives only the handle, no data pointer. Emit empty signal map `[:]` (Swift empty dict) via `individualNfbHandler.send([:])`.

  **`unregisterCallbacks()`** — nil out all 4 callbacks. Each `SetOn*Event` still requires the 3-parameter form `(handle, nil, &error)`. Use a single throwaway `var e = clCError()` variable, reused across all 4 calls — errors during unregistration are safely ignored:
  ```swift
  private func unregisterCallbacks() {
      guard let physio = physio else { return }
      var e = clCError()
      clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nil, &e)
      clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nil, &e)
      clCPhysiologicalStates_SetOnCalibratedEvent(physio, nil, &e)
      clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nil, &e)
      if PhysioBridge.activeBridge === self {
          PhysioBridge.activeBridge = nil
      }
  }
  ```

  **`requirePhysio()`** — private throwing helper that guards access to the `physio` handle, following the same pattern as `DeviceBridge.requireDevice()`:
  ```swift
  private func requirePhysio() throws -> OpaquePointer {
      guard let physio = physio else {
          throw FlutterError(code: "NOT_CREATED",
                             message: "PhysioBridge not created — call create first",
                             details: nil)
      }
      return physio
  }
  ```

  **`startBaselineCalibration()`** — mark as `func startBaselineCalibration() throws`. Guard the handle with `let physio = try requirePhysio()`, then call `clCPhysiologicalStates_StartBaselineCalibration(physio)`. No C error param on this function — the only error source is a nil handle.

  **`importBaselines(map:)`** — mark as `func importBaselines(map:) throws`. Guard the handle with `let physio = try requirePhysio()`, then deserialize `[String: Any]` Dart map to `clCPhysiologicalStates_Baselines` struct:
    - `var baselines = clCPhysiologicalStates_Baselines()`
    - `if let ts = map["ts"] as? Int { baselines.timestampMilli = Int64(ts) }`
    - `if let v = map["alpha"] as? Double { baselines.alpha = Float(v) }` (repeat for `beta`, `alphaGravity`, `betaGravity`, `concentration`)
    - Call `clCPhysiologicalStates_ImportBaselines(physio, &baselines)`. No C error param — call directly.

  **`dispose()`** — call `unregisterCallbacks()`, set `physio = nil`. No `Destroy` function exists.

- [x] **Task 2: Wire PhysioBridge into NeiryKitPlugin** (depends on Task 1)
  Files: `ios/Classes/NeiryKitPlugin.swift`

  **Property:** Add `private var physioBridge: PhysioBridge?` alongside the existing bridge properties.

  **Instantiation:** In `register(with:)`, add `instance.physioBridge = PhysioBridge()` after `emotionsBridge` and before `registerEventChannels()`.

  **Method dispatch:** Add a `handlePhysiologicalCall` method following the same pattern as `handleEmotionsCall`:
    - Guard `physioBridge` and `deviceBridge`.
    - Switch on `call.method`:
      - `"create"` → `let dev = try deviceBridge.requireDevice()`, `try physioBridge.create(device: dev)`, `result(nil)`. Wrap in `do/catch`.
      - `"startBaselineCalibration"` → `try physioBridge.startBaselineCalibration()`, `result(nil)`. Wrap in `do/catch` — `startBaselineCalibration()` throws if `physio` handle is nil.
      - `"importBaselines"` → extract `args?["baselines"] as? [String: Any]`, guard non-nil with `INVALID_ARGS` error, then `try physioBridge.importBaselines(map: baselines)`, `result(nil)`. Wrap in `do/catch` — `importBaselines()` throws if `physio` handle is nil.
      - `"dispose"` → `physioBridge.dispose()`, `result(nil)`.
      - `default` → `result(FlutterMethodNotImplemented)`.

  **Routing:** In `handleMethodCall`, add an `else if channelId == "neiry_kit/physiological"` branch that calls `handlePhysiologicalCall`. Insert it after the `emotions` branch and before the fallthrough `else`.

  **Event channels:** In `registerEventChannels()`:
    - Add a `physioHandlers` dictionary block (same pattern as `emotionsHandlers`): iterate `physioBridge.allStreamHandlers()`.
    - In the `for id in ids` loop, add `else if let handler = physioHandlers[id]` before the `StubStreamHandler` fallback.

  **Cleanup:** In the `"dispose"` case of `handleDeviceLocatorCall`, add `physioBridge?.dispose()` in the teardown chain — insert it after `emotionsBridge?.dispose()` and before `nfbBridge?.dispose()`.

### Phase 2: Dart Compatibility Fix

- [x] **Task 3: Fix PhysioClassifier.individualNfbStream for empty signal** (depends on Task 1)
  Files: `lib/src/api/classifiers/physio_classifier.dart`

  The `IndividualNFBUpdateHandler` callback emits `{}` (empty map) because it carries no data — only a notification that internal NFB state refreshed. The current Dart stream decodes via `NfbUserState.fromMap` which crashes on an empty map (`map['ts'] as int` throws).

  Change the `_individualNfbStream` field and its public getter from `Stream<NfbUserState>` to `Stream<void>`. The decoder should ignore the map contents entirely — it is a notification-only stream:
  ```dart
  late final Stream<void> _individualNfbStream =
      const EventChannel(NeiryEvents.physiologicalIndividualNfb)
          .receiveBroadcastStream({NeiryArgs.serial: _serial})
          .map((_) {});
  ```
  Update the public getter `individualNfbStream` return type to `Stream<void>`. Remove the `NfbUserState` import if it is no longer used anywhere in this file.
