# Code Review: NfbBridge (round 2)

**Plan:** `.ai-factory/plans/22-nfbbridge.md`
**Files changed:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`, `ios/Classes/classifiers/NfbBridge.swift` (new)

## Review-1 issues — all resolved

1. **Enum rawValue type** — Fixed: `UInt32(failReasonRaw)` at `NfbBridge.swift:56`, consistent with all other C enum constructions in the codebase.
2. **Nil guard on calibrator** — Fixed: `guard let calibrator = clCNFBCalibrator_CreateOrGet(device) else { throw ... }` at `NfbBridge.swift:47-49`.
3. **Re-creation cleanup** — Fixed: `if nfb != nil { unregisterCallbacks() }` at the top of both `create` (`NfbBridge.swift:36`) and `createCalibrated` (`NfbBridge.swift:46`).
4. **Locator teardown** — Fixed: `nfbBridge?.dispose()` added at `NeiryKitPlugin.swift:128`, before locator dispose and device release. Correct teardown order: classifier → locator → device.

## Verification checklist

- **C API signatures match headers:** `clCNFB_Create(device, &error)`, `clCNFB_CreateCalibrated(device, calibrator, &error)`, `clCNFBCalibrator_CreateOrGet(device)` (no error param), `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &error)` — all match `CNFB.h` and `CNFBCalibrator.h`.
- **Struct field mapping — `clCNFB_UserState`:** `timestampMilli` (Int64), `delta`/`theta`/`alpha`/`smr`/`beta` (Float) — matches header. Map keys (`ts`, `delta`, `theta`, `alpha`, `smr`, `beta`) match `NfbUserState.fromMap` in Dart.
- **Struct field mapping — `clCIndividualNFBData`:** All 10 fields deserialized with correct types. `ts` → `Int64`, `failReason` → `UInt32` enum, 8 float fields cast from `Double` → `Float`. Keys match `IndividualNfbData.toMap()`.
- **Sentinel handling:** Dart `orNull()` helper uses `(v as num).toDouble()` which handles Swift `Float` arriving as Dart `double` via platform channel codec. Negative values (sentinel `-1.F`) correctly mapped to `null`.
- **Thread safety:** Both callbacks dispatch through `DeviceStreamHandler.send()` which captures the sink reference before `DispatchQueue.main.async`. No data race on sink nullification.
- **Error callback nil-safety:** `msg.map { String(cString: $0) } ?? ""` at `NfbBridge.swift:106` — matches established pattern in `DeviceBridge`.
- **Static weak activeBridge pattern:** Same pattern as `DeviceBridge` and `DeviceLocatorBridge`. Set on `registerCallbacks()`, cleared on `unregisterCallbacks()` with identity check.
- **MethodChannel dispatch:** `neiry_kit/nfb` routed to `handleNfbCall` at `NeiryKitPlugin.swift:56-57`. Method names `create`/`createCalibrated`/`dispose` match `ClassifierMethods` Dart constants.
- **EventChannel wiring:** `nfbHandlers` dict at `NeiryKitPlugin.swift:339-344`, inserted into if/else chain at line 383-384 before `StubStreamHandler` fallback. Channel IDs `neiry_kit/events/nfbState` and `neiry_kit/events/nfbError` match `NeiryEvents` Dart constants.
- **Visibility changes:** Only `DeviceStreamHandler` (`private class` → `class`) and `requireDevice()` (`private func` → `func`) changed in `DeviceBridge.swift`. No behavioral changes.
- **No `clCNFB_Destroy`:** Confirmed — SDK manages lifetime. `dispose()` correctly limited to callback unregistration + handle nil-out.
- **File location:** `ios/Classes/classifiers/NfbBridge.swift` matches ARCHITECTURE.md folder structure.

## New issues

None.

REVIEW_PASS
