## Code Review Summary

**Plan:** `17-devicelocatorbridge.md`
**Files Changed:** 2 (`ios/Classes/DeviceLocatorBridge.swift` — new, `ios/Classes/NeiryKitPlugin.swift` — modified)
**Risk Level:** 🔴 High — compilation failures

### Critical Issues

1. **`FlutterError` does not conform to Swift's `Error` protocol — code will not compile**

   `FlutterError` inherits from `NSObject` (confirmed in `FlutterCodecs.h:246`), NOT from `NSError`. It does not conform to `Error`. Every `throw FlutterError(...)` in the codebase is a compile error:

   - `DeviceLocatorBridge.swift:17` — `checkCError` throws `FlutterError`
   - `DeviceLocatorBridge.swift:62` — `createDevice` guard throws `FlutterError`
   - `DeviceLocatorBridge.swift:82` — `update` guard throws `FlutterError`

   The compiler will emit: `thrown expression type 'FlutterError' does not conform to 'Error'`.

   **Fix:** Add the conformance at the top of `DeviceLocatorBridge.swift` (before the class declaration):

   ```swift
   extension FlutterError: @retroactive Error {}
   ```

   `@retroactive` is required in Swift 5.9+ when conforming an external type to an external protocol. For Swift 5.8 and earlier, omit `@retroactive`.

2. **Non-exhaustive `catch` blocks in `NeiryKitPlugin.swift` — compile error**

   Even after fixing issue 1, the `do/catch` blocks in `handleDeviceLocatorCall` only catch `FlutterError`:

   ```swift
   do {
       try bridge.create(logDirectory: logDirectory)
       result(nil)
   } catch let e as FlutterError {
       result(e)
   }
   ```

   Swift requires exhaustive error handling in non-throwing functions. Since `handleDeviceLocatorCall` is not `throws`, the compiler requires a generic `catch` fallback. Without it: `errors thrown from here are not handled because the enclosing catch is not exhaustive`.

   This affects all 4 do/catch blocks: `create` (line 68), `createDevice` (line 80), `update` (line 95), and the implicit pattern.

   **Fix:** Add a generic catch to each block:

   ```swift
   } catch let e as FlutterError {
       result(e)
   } catch {
       result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
   }
   ```

### Suggestions

1. **`deinit` does not clean up `DeviceLocatorBridge.devices`**

   If the bridge is deallocated without `dispose()` being called (e.g., app killed, plugin deregistered), `deinit` destroys the locator handle but leaves `DeviceLocatorBridge.devices` holding dangling `OpaquePointer` values. The `activeBridge` is `weak` so it self-clears, but `devices` is a strong static dictionary.

   Suggested: add `DeviceLocatorBridge.devices.removeAll()` to `deinit`.

2. **Data race on `activeBridge` and `deviceListSink`**

   These properties are written from the main thread (`onListen`, `onCancel`) and read from the C callback's background BLE thread (the `@convention(c)` handler). There is no synchronization.

   In practice the race window is narrow (BLE scan takes seconds; `onCancel` is unlikely during callback execution), and on 64-bit ARM optional pointer reads/writes are typically atomic. But under Swift's formal memory model this is undefined behavior, and Swift 6 strict concurrency will flag it.

   No immediate fix required — just noting for awareness when the project moves to strict concurrency.

3. **Inline error extraction duplicates `checkCError` logic**

   The `RequestDevices` error path in `onListen` (lines 196–204) manually extracts the error message with `withUnsafePointer`/`withMemoryRebound` instead of reusing `checkCError`. This is justified because `checkCError` throws and `onListen` can't propagate throws — but a non-throwing helper (`func flutterErrorFromCError(_ error: clCError) -> FlutterError?`) would eliminate the duplication and be reusable in future bridges that also need sink-based error reporting.

### Contract Verification

| Dart expectation | Native implementation | Match |
|---|---|---|
| `DeviceLocatorMethods.create` with `{logDirectory: ...}` | `create(logDirectory:)` | OK |
| `DeviceLocatorMethods.createDevice` with `{serial: ...}` | `createDevice(serial:)` with guard | OK |
| `DeviceLocatorMethods.setSingleThreaded` with `{enabled: ...}` | `setSingleThreaded(enabled:)` with guard | OK |
| `DeviceLocatorMethods.update` | `update()` | OK |
| `DeviceLocatorMethods.setLogLevel` with `{level: ...}` | `setLogLevel(level:)` with guard | OK |
| `DeviceLocatorMethods.getVersionString` | inline `clCCapsule_GetVersionString()` | OK |
| `DeviceLocatorMethods.dispose` | `dispose()` | OK |
| `NeiryEvents.deviceList` EventChannel | `onListen`/`onCancel` with `FlutterStreamHandler` | OK |
| `receiveBroadcastStream({deviceType, searchTime})` | `onListen` extracts both from args dict | OK |
| `DeviceInfo.fromMap` expects `{serial: String, name: String, type: int}` | Dict built with matching keys and `Int(…rawValue)` | OK |
| Error code `"1"` → `BluetoothDisabledException` | FailReason mapping uses `"1"` | OK |
| Error code `"255"` → `NeiryErrorCode.unknown` | FailReason mapping uses `"255"` | OK |
| `FlutterEndOfEventStream` constant | Used correctly (verified in `FlutterChannels.h:394`) | OK |

### Positive Notes

- Static weak `activeBridge` pattern is the correct solution for C callbacks without a `void*` context parameter.
- Safe argument extraction with `guard let` + `FlutterError(code: "INVALID_ARGS", ...)` throughout `handleDeviceLocatorCall` — no force unwraps.
- `checkCError` helper using `withUnsafePointer` + `withMemoryRebound` for `char[256]` is the standard Swift idiom.
- `onListen` correctly guards `locator != nil` before using it.
- Device handle storage in `static var devices: [String: OpaquePointer]` prepares for `DeviceBridge` without coupling.
- Thread-safe event dispatch: all `sink()` calls wrapped in `DispatchQueue.main.async {}`.
- `NeiryKitPlugin` wiring is clean: bridge created between `registerMethodChannels()` and `registerEventChannels()`, deviceList channel handler replaced, other channels still use `StubStreamHandler`.
