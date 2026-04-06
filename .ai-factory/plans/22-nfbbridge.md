# Plan: NfbBridge

## Context
Implement the iOS native bridge for the NFB brain-wave classifier (`clCNFB`). The bridge handles `create`/`createCalibrated`/`dispose` MethodChannel calls on `neiry_kit/nfb` and streams `nfbState`/`nfbError` events back to Dart via EventChannels.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Prepare shared utilities

- [x] **Task 1: Make DeviceStreamHandler and DeviceBridge.requireDevice() accessible to NfbBridge**
  Files: `ios/Classes/DeviceBridge.swift`
  Change `DeviceStreamHandler` from `private class` to `class` (internal access) so NfbBridge and future classifier bridges can reuse it.
  Change `DeviceBridge.requireDevice()` from `private func` to `func` (internal access) so the plugin can extract the device handle and pass it to classifier bridges. No other changes to DeviceBridge.

### Phase 2: NfbBridge implementation

- [x] **Task 2: Create NfbBridge** (depends on Task 1)
  Files: `ios/Classes/classifiers/NfbBridge.swift`
  Create `ios/Classes/classifiers/` directory and add `NfbBridge.swift`. Follow the existing DeviceBridge patterns exactly:

  **State:**
  - `private var nfb: OpaquePointer?` — the `clCNFB` handle
  - `private static weak var activeBridge: NfbBridge?` — for C callbacks (same pattern as DeviceBridge, needed because `clCNFB_SetOn*Event` callbacks have no `void* context` param)

  **Stream handlers** (reuse `DeviceStreamHandler` from Task 1):
  - `let nfbStateHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbState")`
  - `let nfbErrorHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbError")`
  - `func allStreamHandlers() -> [(String, FlutterStreamHandler)]` returning both pairs

  **`create(device: OpaquePointer)`** — called by plugin for uncalibrated path:
  - `var error = clCError()` then `nfb = clCNFB_Create(device, &error)` then `try checkCError(error)`
  - Call `registerCallbacks()`

  **`createCalibrated(device: OpaquePointer, calibrationData: [String: Any]?)`** — called by plugin for calibrated path:
  - Get calibrator: `let calibrator = clCNFBCalibrator_CreateOrGet(device)` (no `clCError*`)
  - If `calibrationData` is provided, deserialize it to a `clCIndividualNFBData` C struct and import via `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &error)` then `try checkCError(error)`. Map keys match `IndividualNfbData.toMap()`: `ts` -> `timestampMilli` (Int64), `failReason` -> enum raw value (Int32), `individualFrequency`/`individualPeakFrequency`/`individualPeakFrequencyPower`/`individualPeakFrequencySuppression`/`individualBandwidth`/`individualNormalizedPower`/`lowerFrequency`/`upperFrequency` -> Float fields
  - `nfb = clCNFB_CreateCalibrated(device, calibrator, &error)` then `try checkCError(error)`
  - Call `registerCallbacks()`

  **`dispose()`** — unregister callbacks, set `nfb = nil`, clear `activeBridge` if it points to `self`. No C destroy call (SDK has no `clCNFB_Destroy`).

  **`registerCallbacks()`** private method:
  - Set `NfbBridge.activeBridge = self`
  - `clCNFB_SetOnUserStateChangedEvent(nfb) { _, data in ... }` — guard on `NfbBridge.activeBridge` and `data`, then build map with keys `ts` (Int64 from `data.pointee.timestampMilli`), `delta`/`theta`/`alpha`/`smr`/`beta` (Float from struct fields). Send via `bridge.nfbStateHandler.send(map)`.
  - `clCNFB_SetOnErrorEvent(nfb) { _, msg in ... }` — guard on `NfbBridge.activeBridge`, convert `msg` to `String(cString:)`, send via `bridge.nfbErrorHandler.send(["message": message])`.

  **`unregisterCallbacks()`** private method:
  - `clCNFB_SetOnUserStateChangedEvent(nfb, nil)` and `clCNFB_SetOnErrorEvent(nfb, nil)`
  - Clear `activeBridge` if `=== self`

### Phase 3: Plugin wiring

- [x] **Task 3: Wire NfbBridge into NeiryKitPlugin** (depends on Task 2)
  Files: `ios/Classes/NeiryKitPlugin.swift`

  **Property:** Add `private var nfbBridge: NfbBridge?` alongside existing bridge properties.

  **Initialization:** In `register(with:)`, add `instance.nfbBridge = NfbBridge()` after `deviceBridge` creation, before `registerEventChannels()`.

  **MethodChannel dispatch:** In `handleMethodCall(_:result:channelId:)`, add an `else if channelId == "neiry_kit/nfb"` branch that calls a new `handleNfbCall(_:result:)` method.

  **`handleNfbCall(_:result:)`** — new private method:
  - Guard on `nfbBridge` and `deviceBridge` being non-nil
  - `"create"`: extract `serial` from args (for validation), call `let dev = try deviceBridge.requireDevice()`, then `try nfbBridge.create(device: dev)`, return `result(nil)`. Wrap in `do/catch let e as FlutterError { result(e) } catch { result(FlutterError(...)) }`.
  - `"createCalibrated"`: same as `create` but also extract `calibrationData` from args (`[String: Any]?`), call `try nfbBridge.createCalibrated(device: dev, calibrationData: calibrationData)`.
  - `"dispose"`: call `nfbBridge.dispose()`, return `result(nil)`. No error handling needed (no C destroy call).
  - `default`: `result(FlutterMethodNotImplemented)`

  **EventChannel registration:** In `registerEventChannels()`, build a `nfbHandlers` dict from `nfbBridge.allStreamHandlers()` (same pattern as `deviceHandlers`). In the event channel loop, add `else if let handler = nfbHandlers[id]` before the `StubStreamHandler` fallback so `nfbState` and `nfbError` get real handlers instead of stubs.
