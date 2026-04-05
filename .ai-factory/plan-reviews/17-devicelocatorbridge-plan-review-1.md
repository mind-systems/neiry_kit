## Code Review Summary

**Plan Reviewed:** `17-devicelocatorbridge.md`
**Files Referenced:** 12 (plan, architecture, roadmap, native bridge spec, C SDK headers, Dart API, channel contract, models, exceptions, enums, podspec, NeiryKitPlugin.swift)
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge architecture. `DeviceLocatorBridge` is one bridge class per C API module. EventChannel threading rule (dispatch to `DispatchQueue.main`) is correctly applied. The `FlutterStreamHandler` conformance pattern matches the architecture's code example.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** PASS — plan targets the "DeviceLocatorBridge" milestone. All methods listed in the roadmap (`requestDevices`, `createDevice`, `setSingleThreaded`, `dispose`) are covered, plus additional contract methods (`create`, `update`, `setLogLevel`, `getVersionString`) that are part of the Dart channel contract.

### Critical Issues

1. **Wrong constant name: `FlutterEndOfStream` does not exist — must be `FlutterEndOfEventStream`**
   Task 2 uses `sink(FlutterEndOfStream)` in three places (error path, success path, and the summary description). The correct Flutter iOS constant is `FlutterEndOfEventStream` (defined in `FlutterChannels.h`). Using `FlutterEndOfStream` will cause a compilation error.

   Fix: replace all occurrences of `FlutterEndOfStream` with `FlutterEndOfEventStream`.

2. **Contradictory callback approaches in Task 2 will confuse implementation**
   The first paragraph of the `onListen` description says to use `Unmanaged<DeviceLocatorBridge>.passUnretained(self).toOpaque()` to create a `void*` context and recover `self` inside the callback. The note at the bottom then correctly explains that `clCDeviceLocator_SetOnDeviceListEvent` takes a **bare C function pointer without a `void*` context parameter**, making the `Unmanaged` approach impossible. The correct solution (static weak reference) is only described in the note.

   Having both approaches in the same task is a trap — the implementer reads top-down and will try the `Unmanaged` approach first, waste time, then discover it doesn't work.

   Fix: remove the `Unmanaged` paragraph entirely. Keep only the static weak reference approach and promote it from "note" to the main description. The callback handler must be a non-capturing closure (or a freestanding function) that accesses `DeviceLocatorBridge.activeBridge` through the static property.

3. **Missing nil guard on `locator` inside `onListen`**
   Task 1 correctly establishes the rule: "Every method that uses `locator` must guard that it is non-nil and throw `FlutterError(code: "NO_LOCATOR", ...)`." But Task 2's `onListen` implementation uses `locator` (for `clCDeviceLocator_SetOnDeviceListEvent` and `clCDeviceLocator_RequestDevices`) without mentioning a nil check.

   While the Dart-side FIFO ordering guarantee makes this unlikely in normal operation (the `create` MethodChannel call is dispatched before `receiveBroadcastStream`'s `onListen`), it's still possible in edge cases — for example, if `create` fails silently or if the Dart side is misused. Since `onListen` returns `FlutterError?`, returning `FlutterError(code: "NO_LOCATOR", ...)` when `locator == nil` is trivial and prevents a force-unwrap crash.

   Fix: add an explicit `guard let locator else { return FlutterError(code: "NO_LOCATOR", ...) }` at the top of `onListen`.

### Suggestions

1. **Avoid force unwraps of arguments in Task 3**
   The plan uses `args!["serial"] as! String`, `args!["enabled"] as! Bool`, `args!["level"] as! Int` when dispatching to bridge methods. If the Dart side ever sends a malformed call (or a future refactor changes the argument type), these crash the iOS app instead of returning a `FlutterError`.

   Suggested fix: use `guard let` with fallback to `result(FlutterError(code: "INVALID_ARGS", ...))`:
   ```swift
   guard let args = call.arguments as? [String: Any],
         let serial = args["serial"] as? String else {
       result(FlutterError(code: "INVALID_ARGS", message: "Missing 'serial'", details: nil))
       return
   }
   ```

2. **Make `clCDeviceInfo_GetType` → Int conversion explicit in Task 2**
   The plan says to build the device info dictionary with `"type"` as `Int` but doesn't show the conversion from the C enum return value. `clCDeviceInfo_GetType` returns `clCDeviceType` (a C enum), which needs `.rawValue` in Swift. The Dart side's `DeviceInfo.fromMap` expects an `int` matching `NeiryDeviceType.code` values.

   Suggested: make this explicit in the plan to prevent a type mismatch: `"type": Int(clCDeviceInfo_GetType(info).rawValue)`.

3. **Document the FailReason-to-ErrorCode mapping rationale**
   Task 4 maps `clCDeviceLocator_FailReason_BluetoothDisabled` to `FlutterError(code: "1")` and `_Unknown` to `code: "255"`. These are `clCError_Code` values, not `clCDeviceLocator_FailReason` raw values (which are 1 and 2 respectively). The mapping is correct — verified that `BluetoothDisabledException` uses `NeiryErrorCode.failedToConnect` (code 1) and `NeiryErrorCode.unknown` is 255. But this cross-enum mapping is non-obvious and will puzzle the implementer without a brief comment explaining: "we map FailReason to the clCError_Code that the Dart exception hierarchy expects."

### Positive Notes

- All 7 method names in Task 3 (`create`, `createDevice`, `setSingleThreaded`, `update`, `setLogLevel`, `getVersionString`, `dispose`) match `DeviceLocatorMethods` in `channel_names.dart` exactly.
- The EventChannel ID `"neiry_kit/events/deviceList"` matches `NeiryEvents.deviceList`.
- The device info dictionary keys (`"serial"`, `"name"`, `"type"`) match `DeviceInfo.fromMap` expectations exactly.
- The argument keys (`"logDirectory"`, `"serial"`, `"enabled"`, `"level"`) match `NeiryArgs` constants used by the Dart `DeviceLocator` API.
- The `checkCError` helper's approach for reading `char[256]` via `withUnsafePointer` + `withMemoryRebound` is the standard Swift idiom for C char array conversion.
- Correctly identifies that `getVersionString` should stay inline in `NeiryKitPlugin` (it doesn't need the locator handle).
- The static weak reference pattern for C callbacks without a context parameter is the right solution for this SDK.
- Good forward-thinking: storing `clCDevice` pointers in a static dictionary keyed by serial prepares for `DeviceBridge` without adding a hard cross-bridge dependency.
- Error propagation design is sound: C `clCError` → Swift `FlutterError` → Dart `PlatformException` → `NeiryException` subclass.
