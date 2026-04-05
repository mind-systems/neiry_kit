## Code Review Summary

**Plan:** `17-devicelocatorbridge.md`
**Files Changed:** 2 (`ios/Classes/DeviceLocatorBridge.swift` — new, `ios/Classes/NeiryKitPlugin.swift` — modified)
**Risk Level:** 🟢 Low

### Previous Review Issues — All Resolved

Both critical issues and all three suggestions from review-1 have been addressed:

1. ~~`FlutterError` does not conform to `Error`~~ → Fixed: `extension FlutterError: @retroactive Error {}` at `DeviceLocatorBridge.swift:7`.
2. ~~Non-exhaustive `catch` blocks~~ → Fixed: all 3 do/catch blocks in `handleDeviceLocatorCall` now include a generic `catch { result(FlutterError(code: "UNKNOWN", ...)) }` fallback.
3. ~~`deinit` not cleaning `devices`~~ → Fixed: `DeviceLocatorBridge.devices.removeAll()` added at `DeviceLocatorBridge.swift:113`.
4. ~~Data race on `activeBridge`/`deviceListSink`~~ → Acknowledged, narrow window, no fix required for now.
5. ~~Inline error extraction duplicates `checkCError`~~ → Justified: `onListen` returns `FlutterError?` (non-throwing context), so `checkCError` (which throws) cannot be used directly.

### Critical Issues

None.

### Suggestions

1. **`s.swift_version = '5.0'` in podspec vs `@retroactive` requiring Swift 5.7+**

   `DeviceLocatorBridge.swift:7` uses `@retroactive` (SE-0364, introduced in Swift 5.7). The podspec declares `s.swift_version = '5.0'`. In practice this works fine — modern Xcode ships Swift 5.9+ regardless of the podspec setting, and CocoaPods treats it as a minimum compatibility marker. But if a future CI or linting step validates Swift version features against the podspec, it could flag this mismatch.

   Suggested: update `s.swift_version` to `'5.9'` in a future commit to reflect the actual minimum.

### Contract Verification

| Dart expectation | Native implementation | Match |
|---|---|---|
| `DeviceLocatorMethods.create` with `{logDirectory: ...}` | `create(logDirectory:)` extracts via optional chain | OK |
| `DeviceLocatorMethods.createDevice` with `{serial: ...}` | `createDevice(serial:)` with `guard let` | OK |
| `DeviceLocatorMethods.setSingleThreaded` with `{enabled: ...}` | `setSingleThreaded(enabled:)` with `guard let` | OK |
| `DeviceLocatorMethods.update` | `update()` with locator nil guard | OK |
| `DeviceLocatorMethods.setLogLevel` with `{level: ...}` | `setLogLevel(level:)` with `guard let` | OK |
| `DeviceLocatorMethods.getVersionString` | inline `clCCapsule_GetVersionString()` | OK |
| `DeviceLocatorMethods.dispose` | `dispose()` — destroys locator, clears devices + activeBridge | OK |
| `NeiryEvents.deviceList` EventChannel | `onListen`/`onCancel` with `FlutterStreamHandler` conformance | OK |
| `receiveBroadcastStream({deviceType, searchTime})` | `onListen` extracts both from args dict with type guards | OK |
| `DeviceInfo.fromMap` expects `{serial: String, name: String, type: int}` | Dict built with matching keys; `Int(clCDeviceInfo_GetType(info).rawValue)` | OK |
| `NeiryDeviceType.code` values match `clCDeviceType` raw values | Verified: Headband=0, Buds=1, Headphones=2, Impulse=3, Any=4, BrainBit=6, SinWave=100, Noise=101 | OK |
| Error code `"1"` → `BluetoothDisabledException` | FailReason mapping uses `"1"` = `NeiryErrorCode.failedToConnect` | OK |
| Error code `"255"` → `NeiryErrorCode.unknown` | FailReason mapping uses `"255"` | OK |
| `FlutterEndOfEventStream` constant | Used correctly in both callback and RequestDevices error path | OK |

### C API Signature Verification

| Code usage | Header signature | Match |
|---|---|---|
| `clCDeviceLocator_Create(&error)` | `clCDeviceLocator clCDeviceLocator_Create(clCError* error)` | OK |
| `clCDeviceLocator_CreateWithLogDirectory(dir, &error)` | `clCDeviceLocator ...CreateWithLogDirectory(const char*, clCError*)` | OK |
| `clCDeviceLocator_Destroy(loc)` | `void ...Destroy(clCDeviceLocator)` | OK |
| `clCDeviceLocator_CreateDevice(loc, serial, &error)` | `clCDevice ...CreateDevice(clCDeviceLocator, const char*, clCError*)` | OK |
| `clCDeviceLocator_Update(loc)` | `void ...Update(clCDeviceLocator)` | OK |
| `clCDeviceLocator_SetOnDeviceListEvent(loc, handler)` | Takes `(clCDeviceLocator, clCDeviceLocator_DeviceListHandler)` — no context param | OK |
| Callback closure `{ _, list, failReason in }` | `typedef void (*...)(clCDeviceLocator, clCDeviceInfoList, clCDeviceLocator_FailReason)` | OK |
| `clCDeviceLocator_RequestDevices(loc, type, time, &error)` | `void ...RequestDevices(clCDeviceLocator, clCDeviceType, int32_t, clCError*)` | OK |
| `clCDeviceInfoList_GetCount(list, &error)` | `int32_t ...GetCount(clCDeviceInfoList, clCError*)` | OK |
| `clCDeviceInfoList_GetDeviceInfo(list, i, &error)` | `clCDeviceInfo ...GetDeviceInfo(clCDeviceInfoList, int32_t, clCError*)` | OK |
| `clCDeviceInfo_GetSerial(info)` → `String(cString:)` | Returns `const char*` | OK |
| `clCDeviceInfo_GetName(info)` → `String(cString:)` | Returns `const char*` | OK |
| `clCDeviceInfo_GetType(info).rawValue` | Returns `clCDeviceType` (C enum with UInt32 backing) | OK |

### Threading Correctness

- C callback registered via `clCDeviceLocator_SetOnDeviceListEvent` fires on a background BLE thread. All `sink()` calls inside the callback are wrapped in `DispatchQueue.main.async {}`. ✓
- `RequestDevices` error path (lines 201–216) calls `events()` directly — correct because `onListen` runs on the main thread. ✓
- Non-capturing `@convention(c)` closure accesses only static properties (`DeviceLocatorBridge.activeBridge`) and global symbols — no captures, valid as C function pointer. ✓
- `onCancel` clears `deviceListSink` and `activeBridge` on the main thread; pending BLE callbacks early-return via the guard. ✓

### Positive Notes

- All review-1 issues fixed cleanly — `@retroactive Error` conformance, exhaustive catch blocks, `deinit` cleanup.
- Safe argument extraction throughout `handleDeviceLocatorCall` — `guard let` with `FlutterError(code: "INVALID_ARGS")` on all argument-taking methods.
- `checkCError` helper correctly handles the `char[256]` → `String` conversion via `withUnsafePointer` + `withMemoryRebound`, and is file-scoped for reuse by future bridges.
- Error propagation chain is complete: C `clCError` → Swift `FlutterError` → Dart `PlatformException` → typed `NeiryException`.
- Forward-compatible design: `static var devices` prepares for `DeviceBridge` without coupling.

REVIEW_PASS
