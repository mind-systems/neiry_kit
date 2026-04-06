# Plan: NfbCalibratorBridge (iOS)

## Context

Implement the iOS native bridge for the `clCNFBCalibrator` C API, connecting the existing Dart `NfbCalibrator` API to the native SDK. The bridge handles full 4-stage calibration and quick calibration (both deliver results via EventChannel), plus import/export/query of calibration data.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Bridge class skeleton and MethodChannel wiring

- [x] **Task 1: Create NfbCalibratorBridge.swift with handle, state, and stream handler**
  Files: `ios/Classes/NfbCalibratorBridge.swift`
  Create a new file at `ios/Classes/NfbCalibratorBridge.swift` (same level as `DeviceBridge.swift`, NOT inside `classifiers/` — per ARCHITECTURE.md folder structure). Define `class NfbCalibratorBridge: NSObject` with:
  - `private static weak var activeBridge: NfbCalibratorBridge?` — same static pattern as `NfbBridge` and `DeviceBridge` for C callbacks that have no `void* context`.
  - `private var calibrator: OpaquePointer?` — the cached `clCNFBCalibrator` handle. Never destroyed (SDK caches it per device).
  - `private var currentStage: Int = 0` — tracks which stage the bridge is on, incremented each time the stage-finished callback fires.
  - `private var isQuickMode: Bool = false` — set true when quick calibration is active; used **only** to guard against stage advancement in the stage-finished callback. Does NOT affect how data is delivered (EventChannel is always used).
  - `let calibrationHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbCalibration")` — reuses the existing `DeviceStreamHandler` class from `DeviceBridge.swift` for thread-safe EventChannel dispatch.
  - `func allStreamHandlers() -> [(String, FlutterStreamHandler)]` returning `[(calibrationHandler.channelId, calibrationHandler)]`.

- [x] **Task 2: Wire NfbCalibratorBridge into NeiryKitPlugin**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Add `private var nfbCalibratorBridge: NfbCalibratorBridge?` property alongside the existing bridge properties. In `register(with:)`, instantiate it after `nfbBridge` (`instance.nfbCalibratorBridge = NfbCalibratorBridge()`). In `registerEventChannels()`, build a handler lookup from `nfbCalibratorBridge.allStreamHandlers()` and merge it into the event channel registration loop (same pattern as `nfbHandlers`). In `handleMethodCall`, add an `else if channelId == "neiry_kit/nfb_calibrator"` branch that calls a new `handleNfbCalibratorCall(_:result:)` method. Stub that method with a `switch call.method` dispatching all five method names (`startCalibration`, `stopCalibration`, `importCalibration`, `getCalibration`, `isCalibrated`) to `result(FlutterMethodNotImplemented)` for now — each will be filled in by subsequent tasks.

### Phase 2: Calibration lifecycle methods

- [x] **Task 3: Implement startCalibration — unified for full and quick modes**
  Files: `ios/Classes/NfbCalibratorBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
  Add `func startCalibration(device: OpaquePointer, quick: Bool, result: @escaping FlutterResult) throws` to `NfbCalibratorBridge`:
  1. Call `clCNFBCalibrator_CreateOrGet(device)`. This returns a cached handle with no `clCError*` — do NOT use `do/catch checkCError`. Guard against nil and throw `FlutterError(code: "NULL_HANDLE", ...)` if nil (same pattern as `NfbBridge.createCalibrated`).
  2. Store handle in `self.calibrator`.
  3. Set `currentStage = 0`, `isQuickMode = quick`.
  4. Call `registerCallbacks()` (see Task 4).
  5. If `quick == false` (full mode): call `clCNFBCalibrator_CalibrateIndividualNFB(calibrator, clCIndividualNFBCalibrationStage_1, &error)`, wrap in `do/catch checkCError`.
  6. If `quick == true`: call `clCNFBCalibrator_CalibrateIndividualNFBQuick(calibrator, &error)`, wrap in `do/catch checkCError`.
  7. In both cases, call `result(nil)` immediately on success. The Dart side does not use the MethodChannel return value — it listens on the EventChannel for `CalibrationCompleted` or `CalibrationStageFinished` events.
  In `NeiryKitPlugin.handleNfbCalibratorCall`, wire the `startCalibration` case: extract `quick` flag by checking `args?["calibratorData"] as? String == "quick"` (matching the Dart convention from `NfbCalibrator.calibrateIndividualQuick`), call `deviceBridge.requireDevice()` to get the device handle, then call `nfbCalibratorBridge.startCalibration(device:quick:result:)`.

- [x] **Task 4: Implement C callback registration — stage advancement and completion**
  Files: `ios/Classes/NfbCalibratorBridge.swift`
  Add private `registerCallbacks()` and `unregisterCallbacks()` methods:
  **`registerCallbacks()`:**
  - Set `NfbCalibratorBridge.activeBridge = self`.
  - `clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(calibrator)` — callback receives only `clCNFBCalibrator` handle (no stage number). Inside the callback:
    1. Guard `NfbCalibratorBridge.activeBridge` is alive.
    2. If `isQuickMode` is true, return early — quick mode does not advance stages.
    3. Emit `{'type': 'stage', 'stage': currentStage}` via `calibrationHandler.send(...)`. Note: `currentStage` at this point is 0-indexed (stage1=0). The Dart `CalibrationStage.fromCode()` expects 0-indexed ints.
    4. Increment `currentStage`.
    5. If `currentStage < 4`: call `clCNFBCalibrator_CalibrateIndividualNFB(calibrator, stage, &error)` where `stage` is `clCIndividualNFBCalibrationStage(rawValue: UInt32(currentStage))`. On error, emit error via `calibrationHandler.sendError(...)`. Add a brief code comment noting that re-entering the SDK from its own callback is intentional and safe per the SDK's threading model.
    6. If `currentStage >= 4`: do nothing further — wait for the `onCalibrated` callback.
  - `clCNFBCalibrator_SetOnCalibratedEvent(calibrator)` — callback receives `(clCNFBCalibrator, const clCIndividualNFBData*)`. Inside:
    1. Guard `activeBridge` and data pointer.
    2. Build `dataMap` from the `clCIndividualNFBData` struct with keys matching `IndividualNfbData.fromMap`: `ts`, `failReason`, `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`. Serialize `Float` fields directly without explicit `Double` casting — Flutter's standard message codec handles `Float` correctly, and this matches the existing `NfbBridge` pattern (lines 93–100) which serializes `state.delta`, `state.theta`, etc. as-is.
    3. Emit `{'type': 'done', 'data': dataMap}` via `calibrationHandler.send(...)` — for **both** full and quick modes. The Dart side consumes calibration results exclusively from the EventChannel: `calibrateIndividual()` listens for `CalibrationCompleted` on the stream, and `calibrateIndividualQuick()` (line 204–212 of `nfb_calibrator.dart`) also listens on the same EventChannel, resolving its `Completer<IndividualNfbData>` when it receives `CalibrationCompleted`. The `'done'` event wraps data in a nested `'data'` key — this matches `CalibrationEvent.deserialize` which reads `map['data'] as Map`.
  **`unregisterCallbacks()`:**
  - Pass `nil` to both `clCNFBCalibrator_SetOnCalibrationStageFinishedEvent` and `clCNFBCalibrator_SetOnCalibratedEvent`.
  - Clear `activeBridge` only if `self === activeBridge`.

- [x] **Task 5: Implement stopCalibration**
  Files: `ios/Classes/NfbCalibratorBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
  Add `func stopCalibration()` to `NfbCalibratorBridge`: calls `unregisterCallbacks()`, resets `currentStage = 0`, `isQuickMode = false`. Do NOT call any C API cancel function — there is none. The calibrator is simply left idle; no handle cleanup needed.
  In `NeiryKitPlugin.handleNfbCalibratorCall`, wire the `stopCalibration` case: call `nfbCalibratorBridge.stopCalibration()`, then `result(nil)`.

- [x] **Task 6: Implement importCalibration, getCalibration, isCalibrated**
  Files: `ios/Classes/NfbCalibratorBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
  **`importCalibration(device:data:)`:** Call `clCNFBCalibrator_CreateOrGet(device)` (no `clCError*`), guard nil. Deserialize the Dart `[String: Any]` map into a `clCIndividualNFBData` struct — reuse the exact same field-by-field assignment pattern from `NfbBridge.createCalibrated` (lines 51–65). Call `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &error)`, wrap in `do/catch checkCError`.
  **`getCalibration(device:)`:** Call `clCNFBCalibrator_CreateOrGet(device)`, guard nil → return `nil`. Then call `clCNFBCalibrator_IsCalibrated(calibrator)` — if `false`, return `nil` immediately. This is required because the Dart side (`NfbCalibrator.getCalibrationData()` at `nfb_calibrator.dart:272–277`) checks `result != null` and returns `null` to the caller when no calibration exists — it does NOT catch `PlatformException`. If we skip this guard, two bad things happen: (1) the SDK may error on `GetIndividualNFB` when uncalibrated, producing an unhandled `PlatformException`; (2) the SDK may return a zero/default struct which the bridge would serialize as a non-null map, violating the API contract that says `null` means "no calibration performed or imported yet." Only when `isCalibrated` is true: declare `var data = clCIndividualNFBData()`, call `clCNFBCalibrator_GetIndividualNFB(calibrator, &data, &error)`, wrap in `checkCError`. Serialize the struct back to `[String: Any]` with the same 10 keys (serialize `Float` fields as-is, no explicit `Double` cast). Return the map.
  **`isCalibrated(device:)`:** Call `clCNFBCalibrator_CreateOrGet(device)`, guard nil. Return `clCNFBCalibrator_IsCalibrated(calibrator)` — this returns `Bool` directly with no `clCError*`. Do NOT wrap in `do/catch checkCError`.
  In `NeiryKitPlugin.handleNfbCalibratorCall`, wire all three cases:
  - `importCalibration`: extract `args?["calibratorData"] as? [String: Any]`, call `deviceBridge.requireDevice()`, delegate to bridge.
  - `getCalibration`: call `deviceBridge.requireDevice()`, delegate to bridge, return result map (or `nil` if uncalibrated).
  - `isCalibrated`: call `deviceBridge.requireDevice()`, delegate to bridge, return result Bool.

### Phase 3: Cleanup integration

- [x] **Task 7: Add calibrator cleanup to locator dispose path**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  In the `handleDeviceLocatorCall` `"dispose"` case (line 127), add `nfbCalibratorBridge?.stopCalibration()` before `nfbBridge?.dispose()`. This ensures any in-progress calibration is stopped before the device and locator are torn down. Do NOT call any destroy function on the calibrator handle — the SDK manages its lifecycle.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add NfbCalibratorBridge skeleton and register in NeiryKitPlugin"
- **Commit 2** (after tasks 3-5): "Implement calibration lifecycle — start, stage advancement, stop"
- **Commit 3** (after tasks 6-7): "Implement import/export/query and cleanup on dispose"
