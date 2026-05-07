## Code Review: MEMSBridge iOS

**Plan:** `.ai-factory/plans/46-memsbridge-ios.md`
**Files changed:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`, `ios/Classes/classifiers/MemsBridge.swift` (new)

### SDK Header Verification

Verified all C API usage against `official/iOS/CapsuleClient.framework/Headers/CMEMS.h` and `CMEMSTimedData.h`:

- `clCMEMS_Create(clCDevice, clCError*)` — signature matches, error checked. OK.
- `clCMEMS_CreateCalibrated(clCDevice, clCNFBCalibrator, clCError*)` — signature matches, error checked. OK.
- `clCMEMS_SetOnMEMSTimedDataUpdateEvent(clCMEMS, handler, clCError*)` — takes `clCError*`, code wraps correctly. OK.
- Callback typedef `void (*)(clCMEMS, clCMEMSTimedData)` — two opaque handles, no context param. Bridge uses `{ _, memsData in }`, ignoring the MEMS handle and capturing the data handle. OK.
- `clCMEMSTimedData_GetCount(clCMEMSTimedData) -> int32_t` — no `clCError*`. OK.
- `clCMEMSTimedData_GetAccelerometer(clCMEMSTimedData, int32_t) -> clCPoint3d` — returns struct by value, no `clCError*`. OK.
- `clCMEMSTimedData_GetGyroscope(clCMEMSTimedData, int32_t) -> clCPoint3d` — same. OK.
- `clCMEMSTimedData_GetTimestampMilli(clCMEMSTimedData, int32_t) -> uint64_t` — no `clCError*`. OK.
- `clCPoint3d` struct fields: `float x, y, z`. Accessed via `.x/.y/.z` in Swift. OK.

### Dart Contract Verification

Verified against `lib/src/api/classifiers/mems_classifier.dart` and `lib/src/models/mems_data.dart`:

- Dart sends method names `'create'`, `'createCalibrated'`, `'dispose'` on channel `'neiry_kit/mems'` — native switch cases match all three. OK.
- Dart sends `NeiryArgs.calibrationData` (`'calibrationData'`) key — native reads `args?["calibrationData"]`. OK.
- Dart `memsStream` does `(raw as List).map((e) => MemsSample.fromMap(e as Map<Object?, Object?>))` — expects `List` of maps. Native sends `[[String: Any]]` via `sendList`. Flutter standard codec bridges `Array<Dictionary>` → Dart `List<Map>`. OK.
- `MemsSample.fromMap` reads keys `ax/ay/az/gx/gy/gz/ts` — native map keys match exactly. OK.
- Dart reads `(map['ax'] as num).toDouble()` — Swift `Float` (from `clCPoint3d.x`) → codec → Dart `double` → `num`. OK.
- Dart reads `map['ts'] as int` — Swift `UInt64` (from `GetTimestampMilli`) → codec → Dart `int`. OK.

### MemsBridge.swift

- **Pattern compliance:** Follows `CardioBridge.swift` pattern exactly — static weak `activeBridge`, `DeviceStreamHandler`, `allStreamHandlers()`, `create`/`createCalibrated`/`dispose`/`registerCallbacks`/`unregisterCallbacks`. OK.
- **Thread safety:** Callback captures `bridge` reference on background thread, builds samples array on background thread, then `sendList` dispatches to main thread via `DispatchQueue.main.async` with captured sink. Matches established pattern. OK.
- **Null guard in callback:** Guards both `MemsBridge.activeBridge` and `memsData` for nil. OK.
- **`clCIndividualNFBData` population:** All 10 fields populated, identical to `CardioBridge.createCalibrated`. OK.
- **`unregisterCallbacks`:** Passes `nil` handler to `SetOnMEMSTimedDataUpdateEvent` with `clCError*` (error ignored, consistent with all other bridges). Clears `activeBridge` only if `=== self`. OK.
- **No Destroy call:** Correct per SDK — no `clCMEMS_Destroy` exists.
- **Empty count edge case:** If `GetCount` returns 0, loop doesn't execute, `sendList([])` sends empty array. Dart `.map()` produces empty list. Safe.

### DeviceBridge.swift — `sendList` addition

- Follows exact same capture-then-dispatch pattern as `send` and `sendError`. No existing methods changed. OK.
- `FlutterEventSink` accepts `id _Nullable` — `[[String: Any]]` bridges to `NSArray` which is valid. OK.

### NeiryKitPlugin.swift

- **Property:** `memsBridge` added alongside other bridge properties. OK.
- **Instantiation:** After `productivityBridge`, before `registerEventChannels()`. OK.
- **MethodChannel:** `"neiry_kit/mems"` added to `ids` array. Dispatch branch added in `handleMethodCall`. OK.
- **`handleMemsCall`:** Guards both `memsBridge` and `deviceBridge`. Three cases (`create`, `createCalibrated`, `dispose`) match Dart API exactly. `do/catch` error handling matches all other classifier dispatchers. OK.
- **EventChannel:** `memsHandlers` lookup added. Resolution chain includes `memsHandlers[id]` before `StubStreamHandler` fallback. `"neiry_kit/events/memsData"` already in `ids` array — previously fell to `StubStreamHandler`, now resolves to real handler. OK.
- **Disposal order:** `memsBridge?.dispose()` placed after `nfbCalibratorBridge?.stopCalibration()` and before `cardioBridge?.dispose()`. No ordering dependencies. OK.

### Critical Issues

None.

### Minor Notes

None.

REVIEW_PASS
