## Code Review: DeviceBridge — lifecycle + getters

**Plan:** `.ai-factory/plans/20-devicebridge-lifecycle-getters.md`
**Files Changed:** `ios/Classes/DeviceBridge.swift` (new), `ios/Classes/NeiryKitPlugin.swift` (modified)
**Risk Level:** Medium

### Architecture Compliance

- **No cross-bridge access.** `DeviceBridge` never references `DeviceLocatorBridge`. `requireDevice()` returns the stored handle only. `NeiryKitPlugin` mediates the handoff in `handleDeviceLocatorCall` after `createDevice` succeeds.
- **Dispatch pattern matches existing code.** The `handleDeviceCall` error trampoline (`do/try/catch FlutterError/catch generic`) is identical to `handleDeviceLocatorCall`.
- **Channel contract alignment verified.** All 16 method names in the `switch` match `DeviceMethods` constants exactly. The two intentionally omitted names (`createDevice` — handled by locator channel; `isConnected` — client-side only) are correct.

### Critical Issues

1. **`setDevice` leaks the old handle when `createDevice` is called twice with the same serial**
   `DeviceBridge.swift:38` — the guard `serial != newSerial` skips release when the serial matches. But `clCDeviceLocator_CreateDevice` allocates a new native handle each time it's called — the old handle leaks because it's overwritten without `clCDevice_Release`.

   This was identified in plan-review-2 (suggestion #1) but was not applied to either the plan or the code.

   Scenario: user calls `DeviceLocator.createDevice("ABC")`, then later calls it again with the same serial (retry after error, or reconnect flow where Dart creates a fresh `Device` instance). Handle A leaks.

   Fix — compare pointers, not serials:
   ```swift
   func setDevice(serial newSerial: String, handle: OpaquePointer) {
       if let old = device, old != handle {
           clCDevice_Release(old)
           channelNamesHandle = nil
       }
       device = handle
       serial = newSerial
   }
   ```

### Suggestions

1. **`getMode()` returns `0` when no device is set — maps to `NeiryDeviceMode.resistance`**
   `DeviceBridge.swift:138` — `guard let dev = device else { return 0 }`. Mode code `0` is `resistance` in the Dart enum (`enums.dart:44`). If Dart ever calls `getMode` before `setDevice`, it gets a misleading result instead of an error. Currently safe because Dart tracks mode via the event stream and doesn't invoke `getMode` directly, but the silent wrong answer is fragile. Consider returning `-1` (which would cause `NeiryDeviceMode.fromCode` to throw `ArgumentError`, making the problem visible) or throwing `FlutterError(code: "NO_DEVICE")` and wrapping the dispatch in `do/catch` like the other methods.

2. **`DeviceLocatorBridge.dispose()` leaves `DeviceBridge` holding a potentially stale handle**
   `DeviceLocatorBridge.swift:98-107` — `dispose()` calls `clCDeviceLocator_Destroy` and `devices.removeAll()` but does not coordinate with `DeviceBridge`. If `dispose` is called while a device is connected, `DeviceBridge.device` still holds a valid handle (device handles outlive the locator in the C SDK), but there's no Dart-side cleanup path — `Device.dispose()` calls `disconnect` but never triggers `DeviceBridge.release()`. Not a bug in this PR (handle stays valid), but a gap worth noting: consider calling `deviceBridge?.release()` from the locator `dispose` case in `NeiryKitPlugin`, or adding a dedicated `release` method to the device channel contract.

3. **Dangling pointer in `DeviceLocatorBridge.devices` after `DeviceBridge.release()`**
   After `setDevice` copies the handle to `DeviceBridge.device`, both `DeviceLocatorBridge.devices[serial]` and `DeviceBridge.device` point to the same native object. When `DeviceBridge.release()` calls `clCDevice_Release`, the entry in `DeviceLocatorBridge.devices` becomes a dangling pointer. Currently safe because nothing reads from `devices[serial]` after the handoff (the cross-bridge access was removed), but consider removing the entry from `DeviceLocatorBridge.devices` in the handoff code inside `NeiryKitPlugin`:
   ```swift
   if let handle = DeviceLocatorBridge.devices[serial] {
       deviceBridge?.setDevice(serial: serial, handle: handle)
       DeviceLocatorBridge.devices.removeValue(forKey: serial)
   }
   ```
   This makes ownership transfer explicit and eliminates the dangling pointer entirely.

### Positive Notes

- `requireDevice()` is clean and does not violate architecture rules — uses stored handle only.
- `channelNamesHandle` caching is correctly implemented with `getOrCacheChannelNamesHandle()`, nil-guarded, and cleared in `release()`.
- Return types match Dart expectations precisely: `Float` for sample rates (Dart casts via `(result! as num).toDouble()`), `Int32` for amplitudes, `Int` for battery/mode/type, `[String: Any]` map keys for `getInfo` match `DeviceInfo.fromMap` exactly.
- `disconnect` correctly does NOT call `release()` — the handle stays valid for reconnection.
- Argument key extraction matches `NeiryArgs` constants: `bipolarChannels`, `channelName`, `index`.
- The `@discardableResult` on `stop()` is appropriate since the caller in `handleDeviceCall` uses the return value but other callers might not.
- Null guards on C return values (`guard let info`, `guard let handle`, `guard let cName`) prevent crashes from unexpected nil pointers.
- Error handling trampoline in `handleDeviceCall` is consistent with `handleDeviceLocatorCall`.
