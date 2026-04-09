# Plan: CardioBridge

## Context
Implement the iOS native bridge (`CardioBridge.swift`) for the `clCCardio` classifier and wire it into the plugin dispatcher. The Dart API (`CardioClassifier`), models (`CardioData`, `PpgData`), and channel constants are already implemented — this milestone delivers the native Swift side that makes them functional on iOS.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Bridge implementation

- [x] **Task 1: Create `CardioBridge.swift`**
  Files: `ios/Classes/classifiers/CardioBridge.swift`

  Create a new Swift file following the exact pattern established by `NfbBridge.swift` (two factory paths) and `PhysioBridge.swift` (`registerCallbacks` that `throws` because C setters take `clCError*`).

  **Structure:**
  - `private static weak var activeBridge: CardioBridge?` — C callbacks have no `void* context`, so the static weak reference is the only way to reach the instance (same as NfbBridge/EmotionsBridge).
  - `private var cardio: OpaquePointer?` — the `clCCardio` handle.
  - Three `DeviceStreamHandler` instances:
    - `cardioDataHandler` with channel ID `"neiry_kit/events/cardioData"`
    - `cardioPpgHandler` with channel ID `"neiry_kit/events/ppgData"`
    - `cardioCalibratedHandler` with channel ID `"neiry_kit/events/cardioCalibratedEvent"`
  - `func allStreamHandlers() -> [(String, FlutterStreamHandler)]` returning all three pairs.

  **`create(device:)`:**
  - If `cardio` is non-nil, call `unregisterCallbacks()` first (handles re-creation without Destroy).
  - `var error = clCError()` → `clCCardio_Create(device, &error)` → `try checkCError(error)`.
  - Call `try registerCallbacks()`.

  **`createCalibrated(device:, calibrationData:)`:**
  - Follow `NfbBridge.createCalibrated` pattern exactly:
    1. If `cardio` non-nil, `unregisterCallbacks()`.
    2. `clCNFBCalibrator_CreateOrGet(device)` — guard non-nil, throw `FlutterError(code: "NULL_HANDLE")` on nil.
    3. If `calibrationData` dict is provided, populate a `clCIndividualNFBData` struct from the map (same field-by-field mapping as NfbBridge: `ts` → `Int64`, `failReason` → `UInt32` rawValue, 8 Double→Float fields: `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`), then `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError)` with `try checkCError`.
    4. `clCCardio_CreateCalibrated(device, calibrator, &error)` → `try checkCError(error)`.
  - Call `try registerCallbacks()`.

  **`registerCallbacks()` — must `throws`:**
  All three callbacks (`SetOnIndexesUpdateEvent`, `SetOnPPGDataEvent`, and `SetOnCalibratedEvent`) take `clCError*` — wrap each registration in `var e = clCError()` + `try checkCError(e)` (same pattern as PhysioBridge).

  1. **`clCCardio_SetOnIndexesUpdateEvent`** — callback receives `(clCCardio, const clCCardio_Data*)`. Read struct fields directly (no accessor functions): `timestampMilli` (Int64), `heartRate` (Float), `stressIndex` (Float), `kaplanIndex` (Float), `hasArtifacts` (Bool), `skinContact` (Bool), `motionArtifacts` (Bool), `metricsAvailable` (Bool). Build a `[String: Any]` map with keys matching `CardioData.fromMap`: `ts`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable`. Call `bridge.cardioDataHandler.send(map)`. Note: the C header initializes bool fields to `0.F` (float literal) — this is a header bug but compiles fine on ARM64; read the bool values normally. Register with `clCError*`: `var e = clCError()` → register → `try checkCError(e)`.

  2. **`clCCardio_SetOnPPGDataEvent`** — callback receives a `clCPPGTimedData` handle (not a direct struct). Use the accessor pattern:
     - `let count = clCPPGTimedData_GetCount(ppgData)` — `Int32`.
     - Loop `0..<count`: `clCPPGTimedData_GetValue(ppgData, i)` → `Float`, `clCPPGTimedData_GetTimestampMilli(ppgData, i)` → `UInt64`.
     - Build map: `["sampleCount": count, "values": [Float], "timestamps": [UInt64]]`.
     - Call `bridge.cardioPpgHandler.send(map)`.
     - Register with `clCError*`: `var e = clCError()` → register → `try checkCError(e)`.

  3. **`clCCardio_SetOnCalibratedEvent`** — callback receives only `(clCCardio)` with no data payload. Emit an empty map `[:]` via `bridge.cardioCalibratedHandler.send([:])`. Register with `clCError*`: `var e = clCError()` → register → `try checkCError(e)`.

  **`unregisterCallbacks()`:**
  - Pass `nil` to all three C callback setters (with a local `var e = clCError()` — silently discard errors, matching PhysioBridge's cleanup pattern).
  - Clear `activeBridge` only if `self` is the current instance (`===` check).

  **`dispose()`:**
  - Call `unregisterCallbacks()`, set `cardio = nil`.
  - No `clCCardio_Destroy` call — the SDK has no destroy function for classifiers.

- [x] **Task 2: Wire `CardioBridge` into `NeiryKitPlugin.swift`**
  Files: `ios/Classes/NeiryKitPlugin.swift`

  Follow the exact registration pattern used for `nfbBridge`, `emotionsBridge`, and `physioBridge`:

  1. **Property:** Add `private var cardioBridge: CardioBridge?` alongside the existing bridge properties (after `physioBridge` on line 15).

  2. **Instantiation:** In `register(with:)`, add `instance.cardioBridge = CardioBridge()` after `instance.physioBridge = PhysioBridge()` (before `registerEventChannels()`).

  3. **Method dispatch:** In `handleMethodCall`, add an `else if channelId == "neiry_kit/cardio"` branch calling `handleCardioCall(call, result: result)`. This replaces the current fall-through to `FlutterMethodNotImplemented` for the cardio channel.

  4. **`handleCardioCall` dispatcher:** Create a new private method following `handleNfbCall`'s pattern exactly:
     - Guard both `cardioBridge` and `deviceBridge` non-nil.
     - `"create"` case: `let dev = try deviceBridge.requireDevice()` → `try cardioBridge.create(device: dev)` → `result(nil)`. Standard `do/catch` error wrapping.
     - `"createCalibrated"` case: extract `calibrationData` from args (`call.arguments as? [String: Any]`), then `let dev = try deviceBridge.requireDevice()` → `try cardioBridge.createCalibrated(device: dev, calibrationData: calibrationData)` → `result(nil)`.
     - `"dispose"` case: `cardioBridge.dispose()` → `result(nil)`.
     - `default`: `result(FlutterMethodNotImplemented)`.

  5. **Event channels:** In `registerEventChannels()`, build a `cardioHandlers` lookup dictionary (same pattern as `nfbHandlers`, `emotionsHandlers`, `physioHandlers`):
     ```swift
     var cardioHandlers: [String: FlutterStreamHandler] = [:]
     if let bridge = cardioBridge {
         for (id, handler) in bridge.allStreamHandlers() {
             cardioHandlers[id] = handler
         }
     }
     ```
     Add an `else if let handler = cardioHandlers[id]` branch in the event channel registration cascade, after `physioHandlers` and before the `StubStreamHandler` fallback. This replaces the stubs for `cardioData`, `ppgData`, and `cardioCalibratedEvent`.

  6. **Dispose chain:** In the `"dispose"` case of `handleDeviceLocatorCall`, add `cardioBridge?.dispose()` before the existing classifier disposals (alongside `emotionsBridge?.dispose()`, `physioBridge?.dispose()`, `nfbBridge?.dispose()`).
