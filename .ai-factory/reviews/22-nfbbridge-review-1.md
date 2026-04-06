# Code Review: NfbBridge

**Plan:** `.ai-factory/plans/22-nfbbridge.md`
**Files changed:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`, `ios/Classes/classifiers/NfbBridge.swift` (new)

## Issues

### 1. Enum rawValue type mismatch — will not compile [HIGH]

`NfbBridge.swift:52`
```swift
data.failReason = clCIndividualNFBCalibrationFailReason(rawValue: Int32(failReasonRaw))
```

Every other C enum construction in the codebase uses `UInt32`:
- `DeviceLocatorBridge.swift:94`: `clCCapsule_LogLevel(rawValue: UInt32(level))`
- `DeviceLocatorBridge.swift:197`: `clCDeviceType(rawValue: UInt32(deviceType))`

Swift imports plain C `typedef enum` types with `rawValue: UInt32`. Passing `Int32` here is a type mismatch that prevents compilation.

**Fix:** Change `Int32(failReasonRaw)` to `UInt32(failReasonRaw)`.

### 2. Missing nil guard on `clCNFBCalibrator_CreateOrGet` return [MEDIUM]

`NfbBridge.swift:45`
```swift
let calibrator = clCNFBCalibrator_CreateOrGet(device)
```

C pointer returns without `_Nonnull` annotation are imported as `OpaquePointer!` (implicitly unwrapped optional). If this returns nil (e.g. invalid device state), lines 63 and 67 will crash when the IUO is force-unwrapped.

**Fix:** Add a guard:
```swift
guard let calibrator = clCNFBCalibrator_CreateOrGet(device) else {
    throw FlutterError(code: "NULL_HANDLE", message: "clCNFBCalibrator_CreateOrGet returned nil", details: nil)
}
```

### 3. Re-creation without cleanup leaks stale callbacks [MEDIUM]

`NfbBridge.swift:35-40` and `NfbBridge.swift:44-70`

If `create()` or `createCalibrated()` is called when `nfb` already holds a handle, the old handle's SDK callbacks are not unregistered before overwriting it. The old callbacks remain registered inside the SDK and continue dispatching to `activeBridge`, potentially causing duplicate events.

`DeviceBridge.setDevice()` handles this correctly by calling `unregisterCallbacks()` before overwriting the handle.

**Fix:** Add cleanup at the top of both methods:
```swift
func create(device: OpaquePointer) throws {
    if nfb != nil { unregisterCallbacks() }
    // ... rest unchanged
}
```

Same for `createCalibrated`.

### 4. NfbBridge not disposed on locator teardown [LOW]

`NeiryKitPlugin.swift:127-130` — the `"dispose"` case for device_locator calls `deviceBridge?.release()` but does not call `nfbBridge?.dispose()`. If the Dart side tears down the locator without first disposing the classifier, NFB callbacks remain registered on a released device handle.

The Dart API enforces proper lifecycle ordering (`NfbClassifier.dispose()` before `DeviceLocator.dispose()`), so this is unlikely to trigger in practice. But it's a defensive gap that applies to all future classifier bridges too.

**Fix:** Add `nfbBridge?.dispose()` before `deviceBridge?.release()` in the locator's `"dispose"` case.

## Verified Correct

- **C API signatures match headers:** `clCNFB_Create`, `clCNFB_CreateCalibrated`, `clCNFB_SetOnUserStateChangedEvent`, `clCNFB_SetOnErrorEvent` all match the `CNFB.h` declarations exactly.
- **Struct field names match:** `clCNFB_UserState` fields (`timestampMilli`, `delta`, `theta`, `alpha`, `smr`, `beta`) and `clCIndividualNFBData` fields all correspond correctly between the bridge and the C headers.
- **Map keys match Dart model:** NfbBridge sends `ts`/`delta`/`theta`/`alpha`/`smr`/`beta`; `NfbUserState.fromMap` reads exactly those keys. The `orNull` sentinel helper handles `Float→double` conversion via `(v as num).toDouble()`.
- **Thread safety:** Both callbacks dispatch through `DeviceStreamHandler.send()` which captures the sink and dispatches to `DispatchQueue.main.async`. Matches the established pattern.
- **Error callback nil-safety:** `msg.map { String(cString: $0) } ?? ""` matches the `DeviceBridge.errorHandler` pattern for handling nil `const char*`.
- **No `clCNFB_Destroy`:** Confirmed by header inspection — the SDK manages NFB handle lifetime through the device session. `dispose()` correctly limits itself to callback unregistration.
- **EventChannel wiring:** `nfbHandlers` dict built from `allStreamHandlers()`, inserted into the if/else chain before the `StubStreamHandler` fallback. Channel IDs `neiry_kit/events/nfbState` and `neiry_kit/events/nfbError` match Dart `NeiryEvents` constants exactly.
- **MethodChannel dispatch:** Routes `neiry_kit/nfb` to `handleNfbCall` with correct method names (`create`, `createCalibrated`, `dispose`) matching `ClassifierMethods` Dart constants.
- **Visibility changes to DeviceBridge:** `DeviceStreamHandler` and `requireDevice()` correctly promoted from `private` to internal access. No other changes to DeviceBridge behavior.
