# Plan: MEMSBridge iOS

## Context

Add the iOS native bridge for the MEMS classifier — create `MemsBridge.swift` following the established classifier bridge pattern, then wire it into `NeiryKitPlugin.swift` for MethodChannel dispatch and EventChannel registration.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Stream handler support

- [x] **Task 1: Add `sendList` method to `DeviceStreamHandler`**
  Files: `ios/Classes/DeviceBridge.swift`
  The Dart `MEMSClassifier.memsStream` expects the raw EventChannel event to be a `List` of maps (it does `raw as List` then maps each element to `MemsSample.fromMap`). The existing `DeviceStreamHandler.send(_ map: [String: Any])` only accepts a single dictionary. Add a new method `sendList(_ list: [[String: Any]])` that follows the exact same dispatch pattern: capture `sink`, then `DispatchQueue.main.async { captured?(list) }`. Place it right after the existing `sendError` method. Do not change any existing methods.

### Phase 2: Bridge implementation

- [x] **Task 2: Create `MemsBridge.swift`** (depends on Task 1)
  Files: `ios/Classes/classifiers/MemsBridge.swift`
  Create the bridge class following the `CardioBridge.swift` pattern (closest match — it also has two factory paths with `clCNFBCalibrator_CreateOrGet`). Structure:

  **Static state:** `private static weak var activeBridge: MemsBridge?` — C callbacks have no `void* context`, so the active instance is reached through this static reference.

  **Stream handler:** Single handler `memsDataHandler = DeviceStreamHandler(channelId: "neiry_kit/events/memsData")`. Expose via `allStreamHandlers() -> [(String, FlutterStreamHandler)]` returning the one pair.

  **Instance state:** `private var mems: OpaquePointer?` — the `clCMEMS` handle.

  **`create(device: OpaquePointer)`:** If `mems` is already set, call `unregisterCallbacks()` first. Create via `var error = clCError(); mems = clCMEMS_Create(device, &error); try checkCError(error)`. Then call `try registerCallbacks()`.

  **`createCalibrated(device: OpaquePointer, calibrationData: [String: Any]?)`:** Same guard-and-cleanup. Get calibrator via `clCNFBCalibrator_CreateOrGet(device)` — null-check and throw `FlutterError(code: "NULL_HANDLE", message: "clCNFBCalibrator_CreateOrGet returned nil", details: nil)` if nil. If `calibrationData` is provided, populate a `clCIndividualNFBData` struct (all 10 fields: `timestampMilli`, `failReason`, `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`) and import via `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError); try checkCError(importError)`. Then create via `clCMEMS_CreateCalibrated(device, calibrator, &error); try checkCError(error)`. Copy the exact `clCIndividualNFBData` population block from `CardioBridge.createCalibrated`.

  **`dispose()`:** Call `unregisterCallbacks()`, set `mems = nil`. No `clCMEMS_Destroy` — SDK manages lifetime.

  **`registerCallbacks()`:** Guard `let mems = mems`. Set `MemsBridge.activeBridge = self`. Subscribe: `var e1 = clCError(); clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, { _, memsData in ... }, &e1); try checkCError(e1)`. The subscription call takes `clCError*` — wrap in the `var e / try checkCError` pattern.

  **Callback body:** Guard `let bridge = MemsBridge.activeBridge, let memsData = memsData`. Get count via `clCMEMSTimedData_GetCount(memsData)` — no `clCError*`. Iterate `0..<count`, for each sample: `let accel = clCMEMSTimedData_GetAccelerometer(memsData, i)` (returns `clCPoint3d`, fields `.x/.y/.z`), `let gyro = clCMEMSTimedData_GetGyroscope(memsData, i)`, `let ts = clCMEMSTimedData_GetTimestampMilli(memsData, i)`. Build `[String: Any]` map with keys `ax/ay/az/gx/gy/gz/ts`. Accumulate into `var samples: [[String: Any]]`. After loop, call `bridge.memsDataHandler.sendList(samples)` (the new method from Task 1 handles `DispatchQueue.main.async` dispatch).

  **`unregisterCallbacks()`:** Guard `let mems = mems`. Unsubscribe via `var e = clCError(); clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, nil, &e)`. Clear `activeBridge` if `=== self`.

### Phase 3: Plugin wiring

- [x] **Task 3: Register MemsBridge in NeiryKitPlugin.swift** (depends on Task 2)
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Four changes:

  1. **Property:** Add `private var memsBridge: MemsBridge?` alongside the other bridge properties.

  2. **MethodChannel registration:** Add `"neiry_kit/mems"` to the `ids` array in `registerMethodChannels()`. Add an `else if channelId == "neiry_kit/mems"` branch in `handleMethodCall` that calls a new `handleMemsCall(_:result:)` method.

  3. **Dispatch method:** Create `handleMemsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult)`. Follow the exact pattern from `handleCardioCall`: guard `let memsBridge = memsBridge, let deviceBridge = deviceBridge` with `NOT_INITIALIZED` error. Switch on `call.method`:
     - `"create"`: get device via `try deviceBridge.requireDevice()`, call `try memsBridge.create(device: dev)`, return `result(nil)`. Wrap in `do/catch` (FlutterError + generic).
     - `"createCalibrated"`: extract `calibrationData` from args (same pattern as `handleCardioCall`), get device, call `try memsBridge.createCalibrated(device: dev, calibrationData: calibrationData)`, return `result(nil)`.
     - `"dispose"`: call `memsBridge.dispose()`, return `result(nil)`.
     - `default`: `result(FlutterMethodNotImplemented)`.

  4. **EventChannel registration:** In `registerEventChannels()`, add a `memsHandlers` block (same pattern as other handler lookups): `var memsHandlers: [String: FlutterStreamHandler] = [:]` populated from `memsBridge?.allStreamHandlers()`. In the handler-resolution chain (the `if/else if` ladder inside the `for id in ids` loop), add `else if let handler = memsHandlers[id]` before the `StubStreamHandler` fallback. The `"neiry_kit/events/memsData"` ID is already in the `ids` array — it currently falls through to `StubStreamHandler`, so no change to the array is needed.

  5. **Instantiation:** In `register(with:)`, add `instance.memsBridge = MemsBridge()` — place it after `instance.productivityBridge = ProductivityBridge()`, before `instance.registerEventChannels()`.

  6. **Disposal order:** In `handleDeviceLocatorCall` `"dispose"` case, add `memsBridge?.dispose()` in the teardown sequence — place it alongside other classifier disposals (before `bridge.dispose()` and `deviceBridge?.release()`).
