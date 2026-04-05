# Plan: DeviceBridge — lifecycle + getters

## Context

Implement the iOS `DeviceBridge.swift` — the native bridge that handles device lifecycle commands (`connect`/`disconnect`/`start`/`stop`) and all synchronous/asynchronous getters dispatched from the Dart `Device` class over the `neiry_kit/device` MethodChannel. This milestone does NOT include EventChannel streams (that is a separate milestone).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Bridge skeleton + handle resolution

- [x] **Task 1: Create DeviceBridge class skeleton**
  Files: `ios/Classes/DeviceBridge.swift`
  Create `DeviceBridge` as an `NSObject` subclass (no `FlutterStreamHandler` yet — streams are a later milestone). Include:
  - `private var device: OpaquePointer?` to hold the current `clCDevice` handle.
  - `private var serial: String?` to track which device is active.
  - `private var channelNamesHandle: OpaquePointer?` to cache the `clCDevice_ChannelNames` handle (see Task 5).
  - A `requireDevice() throws -> OpaquePointer` helper that verifies `self.device != nil` and returns it. If `self.device` is nil, throws `FlutterError(code: "NO_DEVICE", message: "No device handle — call createDevice first")`. This helper does NOT access `DeviceLocatorBridge` — the stored handle is set exclusively via `setDevice`.
  - A `setDevice(serial:handle:)` method that `NeiryKitPlugin` calls after `DeviceLocatorBridge.createDevice()` to hand off the handle without cross-calling bridges. Before storing the new handle, if `self.device != nil && self.serial != serial`, call `clCDevice_Release(self.device!)` to prevent native handle leaks when replacing a device. Also nil out `channelNamesHandle` since it belongs to the old device.
  - A `release()` method that calls `clCDevice_Release(device)` if non-nil, nils out `device`, `serial`, and `channelNamesHandle`. Called by `NeiryKitPlugin` during explicit disposal — NOT on disconnect.
  - `deinit` calls `release()` as a safety net.

### Phase 2: Lifecycle methods

- [x] **Task 2: Implement connect, disconnect, start, stop** (depends on Task 1)
  Files: `ios/Classes/DeviceBridge.swift`
  Add four methods following the `checkCError` pattern from `DeviceLocatorBridge.swift`:
  - `connect(_ call: FlutterMethodCall) throws` — extract `bipolarChannels` from args (`args["bipolarChannels"] as? Bool ?? false`), call `clCDevice_Connect(device, bipolarChannels, &error)`, then `try checkCError(error)`.
  - `disconnect() throws` — call `clCDevice_Disconnect(device, &error)` + `checkCError`. Does NOT call `release()` — `disconnect` and `release` are separate C API operations. After disconnect the user can still call `connect()` again on the same handle.
  - `start() throws` — call `clCDevice_Start(device, &error)` + `checkCError`.
  - `stop() throws -> Bool` — call `clCDevice_Stop(device, &error)` + `checkCError`, return `true` on success (Dart expects a `Bool`).
  Each method calls `let device = try requireDevice()` at the top to obtain the validated handle.

### Phase 3: Getters

- [x] **Task 3: Implement getInfo, getBatteryCharge, getMode** (depends on Task 1)
  Files: `ios/Classes/DeviceBridge.swift`
  Three getters with different error-handling requirements:
  - `getInfo() throws -> [String: Any]` — call `clCDevice_GetInfo(device, &error)` + `checkCError`, then read `clCDeviceInfo_GetSerial`, `clCDeviceInfo_GetName`, `clCDeviceInfo_GetType` (these three accessors take NO `clCError*`). Return `["serial": String, "name": String, "type": Int(clCDeviceInfo_GetType(info).rawValue)]` matching `DeviceInfo.fromMap` keys. This matches the existing `DeviceLocatorBridge` pattern which uses `Int(clCDeviceInfo_GetType(info).rawValue)`.
  - `getBatteryCharge() throws -> Int` — call `clCDevice_GetBatteryCharge(device, &error)` + `checkCError`, return `Int(result)` (C returns `uint8_t`).
  - `getMode() -> Int` — call `clCDevice_GetMode(device)` which takes NO `clCError*` parameter. Do NOT wrap in `do/catch checkCError`. Return `Int(result.rawValue)` directly.
  Note: `DeviceMethods.isConnected` exists in the channel contract but is intentionally omitted from this bridge — the Dart `Device` class tracks connectivity client-side via the `connectionStateStream` and a local `_connected` bool. No native query is needed.

- [x] **Task 4: Implement sample rate and PPG amplitude getters** (depends on Task 1)
  Files: `ios/Classes/DeviceBridge.swift`
  Five getters, all following the same pattern — call `let device = try requireDevice()`, call C function with `clCError*`, `checkCError`, return the value:
  - `getEEGSampleRate() throws -> Float` — `clCDevice_GetEEGSampleRate(device, &error)`.
  - `getPPGSampleRate() throws -> Float` — `clCDevice_GetPPGSampleRate(device, &error)`.
  - `getMEMSSampleRate() throws -> Float` — `clCDevice_GetMEMSSampleRate(device, &error)`.
  - `getPPGIrAmplitude() throws -> Int32` — `clCDevice_GetPPGIrAmplitude(device, &error)`.
  - `getPPGRedAmplitude() throws -> Int32` — `clCDevice_GetPPGRedAmplitude(device, &error)`.
  Return `Float` for sample rates (Dart receives as `num`, calls `.toDouble()`), `Int32` for amplitudes (Dart receives as `int`).

- [x] **Task 5: Implement channel names accessors** (depends on Task 1)
  Files: `ios/Classes/DeviceBridge.swift`
  Channel names use a two-step handle pattern — first obtain a `clCDevice_ChannelNames` handle, then call accessors on it. The handle MUST be cached in `self.channelNamesHandle` (declared in Task 1) because there is no `clCDevice_ChannelNames_Release` or `_Destroy` in the SDK — repeated calls to `clCDevice_GetChannelNames` may allocate new handles with no way to free old ones. On first access, store the handle; on subsequent calls, reuse it. Clear the cache in `release()`.
  - `getChannelNames() throws -> [String]` — get or reuse cached handle via `clCDevice_GetChannelNames(device, &error)` + `checkCError`. Then call `clCDevice_ChannelNames_GetChannelsCount(handle, &error)` + `checkCError` to get the count. Loop `0..<count`, calling `clCDevice_ChannelNames_GetChannelNameByIndex(handle, i, &error)` + `checkCError` for each, collecting into a `[String]`. Return the array.
  - `getChannelsCount() throws -> Int` — get or reuse cached handle, then `clCDevice_ChannelNames_GetChannelsCount(handle, &error)`, return `Int(count)`.
  - `getChannelIndexByName(_ call: FlutterMethodCall) throws -> Int` — extract `channelName` from args, get or reuse cached handle, call `clCDevice_ChannelNames_GetChannelIndexByName(handle, channelName, &error)` + `checkCError`, return `Int(result)`.
  - `getChannelNameByIndex(_ call: FlutterMethodCall) throws -> String` — extract `index` from args, get or reuse cached handle, call `clCDevice_ChannelNames_GetChannelNameByIndex(handle, Int32(index), &error)`, return `String(cString: result)`.
  Add a private helper `getOrCacheChannelNamesHandle() throws -> OpaquePointer` that returns `channelNamesHandle` if non-nil, otherwise calls `clCDevice_GetChannelNames`, stores the result, and returns it.

### Phase 4: Plugin wiring

- [x] **Task 6: Wire DeviceBridge into NeiryKitPlugin** (depends on Tasks 2–5)
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Integrate `DeviceBridge` into the plugin dispatch:
  - Add `private var deviceBridge: DeviceBridge?` property alongside `deviceLocatorBridge`.
  - In `register(with:)`, instantiate `DeviceBridge()` after `DeviceLocatorBridge()`.
  - In `handleMethodCall`, add an `else if channelId == "neiry_kit/device"` branch that calls a new `handleDeviceCall(_:result:)` method.
  - Implement `handleDeviceCall` with a `switch call.method` dispatching to all DeviceBridge methods (connect, disconnect, start, stop, getInfo, getBatteryCharge, getMode, getEEGSampleRate, getPPGSampleRate, getMEMSSampleRate, getPPGIrAmplitude, getPPGRedAmplitude, getChannelNames, getChannelsCount, getChannelIndexByName, getChannelNameByIndex). Follow the existing error-handling trampoline pattern (`do { try ... result(value) } catch let e as FlutterError { result(e) } catch { result(FlutterError(...)) }`). For `getMode` (which does not throw), call directly and return `result(bridge.getMode())` — no `do/catch`.
  - `disconnect` dispatch calls only `bridge.disconnect()` — does NOT call `release()`. The device handle remains valid after disconnect so the user can reconnect.
  - Handle device handle handoff: after `deviceLocatorBridge.createDevice(serial:)` succeeds in `handleDeviceLocatorCall`, call `deviceBridge?.setDevice(serial:handle:)` passing the handle from `DeviceLocatorBridge.devices[serial]`. This is the coordination point — `NeiryKitPlugin` mediates, bridges never cross-call each other.

## Commit Plan
- **Commit 1** (after tasks 1–2): "Add DeviceBridge skeleton with lifecycle methods"
- **Commit 2** (after tasks 3–5): "Implement all DeviceBridge getters including channel names"
- **Commit 3** (after task 6): "Wire DeviceBridge into NeiryKitPlugin dispatch"
