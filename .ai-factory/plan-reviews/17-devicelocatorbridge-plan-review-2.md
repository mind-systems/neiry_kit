## Code Review Summary

**Plan Reviewed:** `17-devicelocatorbridge.md`
**Files Referenced:** 14 (plan, architecture, roadmap, native bridge spec, C SDK headers — CDeviceLocator.h / CDeviceInfo.h / CDeviceInfoList.h / CError.h / CDefinesPrivate.h, Dart API — device_locator.dart / device.dart, channel_names.dart, enums.dart, neiry_exception.dart, neiry_error_code.dart, NeiryKitPlugin.swift, NeiryKitBridge.h, podspec)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge architecture exactly. One bridge class per C API module (`DeviceLocatorBridge` wraps `clCDeviceLocator_*`). EventChannel threading rule (dispatch to `DispatchQueue.main.async`) is correctly applied. Error propagation chain (C `clCError` → Swift `FlutterError` → Dart `PlatformException` → typed `NeiryException`) matches the architecture's specification.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** PASS — plan targets the "DeviceLocatorBridge" milestone. All methods listed in the roadmap (`requestDevices`, `createDevice`, `setSingleThreaded`, `dispose`) are covered, plus additional contract methods (`create`, `update`, `setLogLevel`, `getVersionString`) that are part of the Dart channel contract.
- **Skill context:** file not present — WARN (non-blocking).

### Previous Review Issues — All Resolved

All three critical issues and three suggestions from `17-devicelocatorbridge-plan-review-1.md` have been addressed:

1. ~~`FlutterEndOfStream` typo~~ → corrected to `FlutterEndOfEventStream` throughout Task 2.
2. ~~Contradictory Unmanaged vs static weak reference~~ → `Unmanaged` approach removed entirely; static weak `activeBridge` is now the sole, clearly-described mechanism.
3. ~~Missing nil guard on `locator` in `onListen`~~ → explicit `guard let locator = self.locator else { return FlutterError(...) }` added at the top of `onListen`.
4. ~~Force unwraps of arguments in Task 3~~ → replaced with `guard let` + `FlutterError` fallback pattern, with code example.
5. ~~Implicit `clCDeviceInfo_GetType` conversion~~ → now explicit: `Int(clCDeviceInfo_GetType(info).rawValue)`.
6. ~~Undocumented FailReason-to-ErrorCode mapping~~ → rationale now inline: explains that `"1"` maps to `NeiryErrorCode.failedToConnect` / `BluetoothDisabledException` and `"255"` maps to `NeiryErrorCode.unknown`.

### Verification Against C API Headers

All C function signatures in the plan match the actual SDK headers:

| Plan reference | Actual signature | Match |
|---|---|---|
| `clCDeviceLocator_Create(&error)` | `clCDeviceLocator clCDeviceLocator_Create(clCError* error)` | ✓ |
| `clCDeviceLocator_CreateWithLogDirectory(dir, &error)` | `...CreateWithLogDirectory(const char*, clCError*)` | ✓ |
| `clCDeviceLocator_Destroy(locator!)` | `void ...Destroy(clCDeviceLocator)` | ✓ |
| `clCDeviceLocator_CreateDevice(locator!, serial, &error)` | `clCDevice ...CreateDevice(clCDeviceLocator, const char*, clCError*)` | ✓ |
| `clCDeviceLocator_SetOnDeviceListEvent(locator, handler)` | Takes `(clCDeviceLocator, handler)` — no context/userdata param | ✓ |
| Callback: `(OpaquePointer?, OpaquePointer?, clCDeviceLocator_FailReason)` | `void handler(clCDeviceLocator, clCDeviceInfoList, clCDeviceLocator_FailReason)` | ✓ |
| `clCDeviceLocator_RequestDevices(locator, type, time, &error)` | `void ...RequestDevices(clCDeviceLocator, clCDeviceType, int32_t, clCError*)` | ✓ |
| `clCCapsule_SetSingleThreaded(enabled)` | `void ...SetSingleThreaded(bool)` | ✓ |
| `clCCapsule_SetLogLevel(clCCapsule_LogLevel(...))` | `void ...SetLogLevel(clCCapsule_LogLevel)` | ✓ |
| `clCDeviceInfoList_GetCount(list, &error)` | `int32_t ...GetCount(clCDeviceInfoList, clCError*)` | ✓ |
| `clCDeviceInfoList_GetDeviceInfo(list, i, &error)` | `clCDeviceInfo ...GetDeviceInfo(clCDeviceInfoList, int32_t, clCError*)` | ✓ |

### Verification Against Dart Contract

| Dart expectation | Plan implementation | Match |
|---|---|---|
| `DeviceLocatorMethods.create` with `{logDirectory: ...}` | Task 1 `create(logDirectory:)` | ✓ |
| `receiveBroadcastStream({deviceType: code, searchTime: int})` | Task 2 `onListen` extracts both from arguments dict | ✓ |
| `DeviceLocatorMethods.createDevice` with `{serial: ...}` | Task 1 `createDevice(serial:)` | ✓ |
| `DeviceInfo.fromMap` expects `{serial: String, name: String, type: int}` | Task 2 builds matching `[String: Any]` dict | ✓ |
| `NeiryDeviceType.fromCode(int)` — int must match `clCDeviceType` raw values | `Int(clCDeviceInfo_GetType(info).rawValue)` | ✓ |
| Error code `"1"` → `BluetoothDisabledException` | FailReason mapping uses `"1"` | ✓ |
| Error code `"255"` → `NeiryErrorCode.unknown` | FailReason mapping uses `"255"` | ✓ |
| All 7 method names match `DeviceLocatorMethods` constants | Verified against `channel_names.dart` | ✓ |
| EventChannel `neiry_kit/events/deviceList` | Matches `NeiryEvents.deviceList` and `NeiryKitPlugin.swift` registration | ✓ |

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- The static weak `activeBridge` pattern is the correct solution for C callbacks that lack a `void* context` parameter. The `weak` qualifier prevents retain cycles and the singleton nature of `DeviceLocator` (enforced by the Dart side) guarantees only one active bridge exists at a time.
- The `checkCError` helper's `withUnsafePointer(to:) + withMemoryRebound(to:capacity:)` approach for reading the fixed-size `char[256]` message buffer is the standard Swift idiom and correctly handles the tuple-to-pointer conversion.
- Forward-thinking design: storing `clCDevice` pointers in `static var devices: [String: OpaquePointer]` keyed by serial prepares for `DeviceBridge` lookup without introducing a hard cross-bridge dependency.
- Task 3's wiring instructions align precisely with the existing `NeiryKitPlugin.swift` structure — inserts bridge creation between `registerMethodChannels()` and `registerEventChannels()`, replaces the `StubStreamHandler` for `deviceList` only, and keeps `getVersionString` inline.
- The `deinit` safety net in Task 1 ensures native resource cleanup even if Dart's `dispose()` is never called (e.g., app killed mid-session).
- Thread safety in Task 2 is handled correctly: the `@convention(c)` closure captures nothing, reads from static/instance vars, then dispatches all `sink()` calls to `DispatchQueue.main.async` — matching the architecture's threading rule.

PLAN_REVIEW_PASS
