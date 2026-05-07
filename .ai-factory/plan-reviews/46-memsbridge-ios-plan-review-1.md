## Plan Review: MEMSBridge iOS

**Plan file:** `.ai-factory/plans/46-memsbridge-ios.md`
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows "one bridge class per C API module" and places files at the correct paths (`ios/Classes/classifiers/MemsBridge.swift`). Dependency rule respected (platform bridge calls C SDK only, no cross-bridge calls).
- **RULES.md:** not present (WARN — non-blocking).
- **ROADMAP.md:** PASS — plan implements the `MEMSBridge iOS` milestone item exactly as specified. C API functions, error handling patterns, and EventChannel ID all match the roadmap description.

### Critical Issues

None.

### Verified Against SDK Headers

- `clCMEMS_Create(clCDevice, clCError*)` — confirmed in `CMEMS.h`
- `clCMEMS_CreateCalibrated(clCDevice, clCNFBCalibrator, clCError*)` — confirmed
- `clCMEMS_SetOnMEMSTimedDataUpdateEvent(clCMEMS, handler, clCError*)` — confirmed; takes `clCError*`
- Callback typedef `void (*)(clCMEMS, clCMEMSTimedData)` — no context param, two opaque handles (not struct pointers)
- `clCMEMSTimedData_GetCount(clCMEMSTimedData) -> int32_t` — no `clCError*`, confirmed
- `clCMEMSTimedData_GetAccelerometer(clCMEMSTimedData, int32_t) -> clCPoint3d` — no `clCError*`, confirmed
- `clCMEMSTimedData_GetGyroscope(clCMEMSTimedData, int32_t) -> clCPoint3d` — no `clCError*`, confirmed
- `clCMEMSTimedData_GetTimestampMilli(clCMEMSTimedData, int32_t) -> uint64_t` — no `clCError*`, confirmed
- `clCPoint3d` struct: `{ float x; float y; float z; }` — confirmed

### Verified Against Codebase

- **Dart `MEMSClassifier.memsStream`** does `(raw as List).map((e) => MemsSample.fromMap(e as Map<Object?, Object?>)).toList()` — expects the native event to be a `List` of maps. The plan's `sendList` addition and `[[String: Any]]` dispatch are the correct solution.
- **`MemsSample.fromMap`** reads keys `ax/ay/az/gx/gy/gz/ts` — plan's map key set matches exactly.
- **`NeiryChannels.mems`** = `'neiry_kit/mems'` already defined in `channel_names.dart` — plan correctly references this.
- **`NeiryEvents.memsData`** = `'neiry_kit/events/memsData'` already defined — plan correctly identifies it's already in the EventChannel `ids` array (line 684 of `NeiryKitPlugin.swift`).
- **`DeviceStreamHandler`** currently has `send(_: [String: Any])` and `sendError` — no list-sending variant exists. Task 1 is necessary.
- **`CardioBridge.swift`** pattern (static weak `activeBridge`, `allStreamHandlers()`, `create`/`createCalibrated`/`dispose`/`registerCallbacks`/`unregisterCallbacks`) — plan mirrors this exactly.
- **`NeiryKitPlugin.swift`** plugin wiring: existing if/else chain in `handleMethodCall`, handler-resolution chain in `registerEventChannels`, and disposal sequence in `handleDeviceLocatorCall "dispose"` — plan targets all correct insertion points.

### Minor Notes

1. **Task 3 heading says "Four changes" but lists 6 sub-items.** Cosmetic inconsistency — will not cause implementation errors since each sub-item is clearly described.

2. **`Int32` loop range in callback.** The plan says `for i in 0..<count` where `count` comes from `clCMEMSTimedData_GetCount` (returns `Int32` in Swift). The integer literal `0` will infer as `Int32` from context, so this works. Implementer should be aware in case Swift's type checker complains — a simple `Int32(0)..<count` resolves it.

### Positive Notes

- The plan correctly identifies that MEMS callback params are opaque handles (not struct pointers like Cardio's `clCCardio_Indexes*`), so accessor functions are used instead of `.pointee`.
- Proper thread-safety: captures `sink` before `DispatchQueue.main.async`, following the established `DeviceStreamHandler` pattern.
- Correct identification that no `clCMEMS_Destroy` exists — matches the SDK's handle-lifetime management for classifiers.
- The `sendList` method correctly follows the same capture-then-dispatch pattern as `send`, avoiding race conditions on sink assignment.
- Plan correctly places `memsBridge?.dispose()` in the teardown sequence alongside other classifier disposals.

PLAN_REVIEW_PASS
