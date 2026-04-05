# Plan: DeviceLocatorBridge (iOS)

## Context

Implement the iOS-side `DeviceLocatorBridge.swift` that holds an `OpaquePointer?` to the native `clCDeviceLocator`, handles all MethodChannel calls on `neiry_kit/device_locator`, and streams the device list via `neiry_kit/events/deviceList` EventChannel. This is the first real native bridge — all subsequent iOS bridges will follow the same patterns established here.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: DeviceLocatorBridge class

- [x] **Task 1: Create DeviceLocatorBridge.swift with lifecycle methods**
  Files: `ios/Classes/DeviceLocatorBridge.swift`
  Create a new `DeviceLocatorBridge` class. It owns a private `var locator: OpaquePointer?` — the handle to `clCDeviceLocator`. Also declare `static var devices: [String: OpaquePointer] = [:]` to store device handles created by `createDevice` (keyed by serial), so the future `DeviceBridge` can look them up. Implement the following methods that will be called from the MethodChannel handler:

  - `create(logDirectory: String?)` — calls `clCDeviceLocator_CreateWithLogDirectory(dir, &error)` when `logDirectory` is non-nil, otherwise `clCDeviceLocator_Create(&error)`. Stores the returned `OpaquePointer` in `self.locator`. Checks error via the `checkCError` helper (Task 4) and throws `FlutterError` on failure.
  - `createDevice(serial: String) -> Any?` — calls `clCDeviceLocator_CreateDevice(locator!, serial, &error)`. Stores the returned `clCDevice` pointer in `DeviceLocatorBridge.devices[serial]`. Returns `nil` on success (Dart side constructs `Device` locally). Throws `FlutterError` on C error.
  - `setSingleThreaded(enabled: Bool)` — calls `clCCapsule_SetSingleThreaded(enabled)`.
  - `update()` — calls `clCDeviceLocator_Update(locator!)`.
  - `setLogLevel(level: Int)` — calls `clCCapsule_SetLogLevel(clCCapsule_LogLevel(rawValue: UInt32(level)))`.
  - `dispose()` — calls `clCDeviceLocator_Destroy(locator!)`, sets `locator = nil`, clears `DeviceLocatorBridge.devices`, clears `DeviceLocatorBridge.activeBridge` if it points to `self`.
  - `deinit` — if `locator != nil`, calls `clCDeviceLocator_Destroy(locator!)` as a safety net.

  Every method that uses `locator` must guard that it is non-nil and throw `FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil)` if it is.

  Follow the error pattern from the spec: create a `var error = clCError()`, pass `&error`, check with `try checkCError(error)`.

- [x] **Task 2: Implement FlutterStreamHandler for deviceList EventChannel**
  Files: `ios/Classes/DeviceLocatorBridge.swift`
  Make `DeviceLocatorBridge` conform to `FlutterStreamHandler` (extend `NSObject`). Add a `private static weak var activeBridge: DeviceLocatorBridge?` property — this is the mechanism for C callbacks to reach the bridge instance, since `clCDeviceLocator_SetOnDeviceListEvent` takes a bare C function pointer without a `void* context` parameter. Implement:

  - `onListen(withArguments:eventSink:)` — first, guard that `locator` is non-nil: `guard let locator = self.locator else { return FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil) }`. Extract `deviceType` (Int) and `searchTime` (Int) from the arguments dictionary. Store the `eventSink` in `private var deviceListSink: FlutterEventSink?`. Set `DeviceLocatorBridge.activeBridge = self`.

    Register the C callback via `clCDeviceLocator_SetOnDeviceListEvent(locator, handler)` where `handler` is a **freestanding C function** (or a non-capturing `@convention(c)` closure). The handler cannot capture `self` — it must access the bridge instance through the static `DeviceLocatorBridge.activeBridge` property:

    ```swift
    let handler: @convention(c) (OpaquePointer?, OpaquePointer?, clCDeviceLocator_FailReason) -> Void = { _, list, failReason in
        guard let bridge = DeviceLocatorBridge.activeBridge,
              let sink = bridge.deviceListSink else { return }
        // ... build result on this background thread, then dispatch to main
    }
    ```

    Inside the handler:
    1. If `failReason != .OK` — build a `FlutterError`. Map `clCDeviceLocator_FailReason_BluetoothDisabled` to `FlutterError(code: "1", message: "Bluetooth is disabled", details: nil)` and `_Unknown` to `FlutterError(code: "255", ...)`. The code values are `clCError_Code` integers that the Dart exception hierarchy expects — `"1"` maps to `NeiryErrorCode.failedToConnect` which the Dart side wraps as `BluetoothDisabledException`, `"255"` maps to `NeiryErrorCode.unknown`. Dispatch to main: `DispatchQueue.main.async { sink(error); sink(FlutterEndOfEventStream) }`.
    2. Otherwise — iterate the device list: call `clCDeviceInfoList_GetCount(list, &error)` to get `count`, then loop `0..<count` calling `clCDeviceInfoList_GetDeviceInfo(list, i, &error)` for each `clCDeviceInfo`. Extract `serial` via `clCDeviceInfo_GetSerial`, `name` via `clCDeviceInfo_GetName`, `type` via `Int(clCDeviceInfo_GetType(info).rawValue)` (the `.rawValue` conversion is required because `clCDeviceInfo_GetType` returns a `clCDeviceType` C enum, and the Dart `DeviceInfo.fromMap` expects a plain `int` matching `NeiryDeviceType.code`). Build an array of `[String: Any]` dictionaries with keys `"serial"`, `"name"`, `"type"`.
    3. Dispatch to main thread: `DispatchQueue.main.async { sink(devicesArray); sink(FlutterEndOfEventStream) }`.

    After registering the callback, call `clCDeviceLocator_RequestDevices(locator, clCDeviceType(rawValue: UInt32(deviceType)), Int32(searchTime), &error)`. Check the error and if it fails, send error to sink and end the stream.

  - `onCancel(withArguments:)` — set `deviceListSink = nil`. If `DeviceLocatorBridge.activeBridge === self`, clear it to `nil`. Optionally unregister the C callback by calling `clCDeviceLocator_SetOnDeviceListEvent(locator, nil)`.

- [x] **Task 3: Wire DeviceLocatorBridge into NeiryKitPlugin**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Replace the stub handling in `NeiryKitPlugin` so the `DeviceLocatorBridge` actually receives calls:

  1. Add a `private var deviceLocatorBridge: DeviceLocatorBridge?` property to `NeiryKitPlugin`.
  2. In `register(with:)`, instantiate `DeviceLocatorBridge()` after `registerMethodChannels()` but before `registerEventChannels()`, store it in `instance.deviceLocatorBridge`.
  3. In `registerEventChannels()`, for the `"neiry_kit/events/deviceList"` channel, set the stream handler to `deviceLocatorBridge` instead of `StubStreamHandler()`.
  4. In `handleMethodCall`, for `channelId == "neiry_kit/device_locator"`, dispatch all 7 methods to the bridge using safe argument extraction. Use `guard let` with `FlutterError` fallback instead of force unwraps:

     ```swift
     case "createDevice":
         guard let args = call.arguments as? [String: Any],
               let serial = args["serial"] as? String else {
             result(FlutterError(code: "INVALID_ARGS", message: "Missing 'serial'", details: nil))
             return
         }
         do {
             let ret = try deviceLocatorBridge.createDevice(serial: serial)
             result(ret)
         } catch let e as FlutterError {
             result(e)
         }
     ```

     Apply the same `guard let` pattern for all methods that take arguments:
     - `"create"` → `let logDirectory = (call.arguments as? [String: Any])?["logDirectory"] as? String` (optional, nil is valid)
     - `"createDevice"` → guard `serial` as `String`
     - `"setSingleThreaded"` → guard `enabled` as `Bool`
     - `"setLogLevel"` → guard `level` as `Int`
     - `"update"` → no arguments needed
     - `"getVersionString"` → keep the existing inline implementation
     - `"dispose"` → no arguments needed

  5. Wrap each bridge call in `do { try ... result(nil) } catch let e as FlutterError { result(e) }` to propagate errors back to Dart as `PlatformException`.

### Phase 2: Error handling and robustness

- [x] **Task 4: Extract a reusable clCError-to-FlutterError helper**
  Files: `ios/Classes/DeviceLocatorBridge.swift`
  The pattern of checking `error.success` and creating a `FlutterError` will be repeated in every bridge. Extract a file-scope helper function:

  ```swift
  func checkCError(_ error: clCError) throws {
      guard error.success else {
          throw FlutterError(
              code: String(error.code.rawValue),
              message: withUnsafePointer(to: error.message) {
                  $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                      String(cString: $0)
                  }
              },
              details: nil
          )
      }
  }
  ```

  The `error.message` is a fixed-size C char array (`char[256]`), not a `const char*`. Use `withUnsafePointer` + `withMemoryRebound` to safely read it as a C string. Apply this helper in all `create`, `createDevice`, `requestDevices`, and `update` calls, replacing any inline error checks from Task 1.

  Keep this helper inside `DeviceLocatorBridge.swift` for now. When `DeviceBridge` is implemented in the next milestone, it can be moved to a shared file (e.g., `ios/Classes/CErrorHelpers.swift`).
