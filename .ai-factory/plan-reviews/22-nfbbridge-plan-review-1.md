# Plan Review: NfbBridge

**Plan file:** `.ai-factory/plans/22-nfbbridge.md`
**Files reviewed:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`, `ios/Classes/DeviceLocatorBridge.swift`, `lib/src/api/classifiers/nfb_classifier.dart`, `lib/src/models/individual_nfb_data.dart`, `lib/src/channel/channel_names.dart`, SDK headers (`CNFB.h`, `CNFBCalibrator.h`)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** PASS. Plan follows all dependency rules. Plugin mediates between bridges (not bridges cross-calling each other). Separate MethodChannel per bridge matches the anti-pattern rule. `DeviceStreamHandler` reuse is a shared utility, not a cross-bridge call.
- **RULES.md:** Not present (WARN — non-blocking).
- **ROADMAP.md:** WARN. The roadmap entry for NfbBridge says "MethodChannel dispatch shared on `neiry_kit/device`" but the plan correctly routes through `neiry_kit/nfb`, which matches the Dart API (`NeiryChannels.nfb = 'neiry_kit/nfb'`) and the architecture's anti-pattern against sharing a single MethodChannel. The roadmap description is stale — consider updating it after this milestone completes.

## Critical Issues

None.

## Suggestions

1. **Add nil check for `clCNFBCalibrator_CreateOrGet` return value** (Task 2, `createCalibrated`)

   `clCNFBCalibrator_CreateOrGet(device)` has no `clCError*` parameter, but in Swift the return type is `OpaquePointer?`. A nil return (e.g., if the device handle is invalid) would crash when passed to `clCNFB_CreateCalibrated`. Add a guard:

   ```swift
   let calibrator = clCNFBCalibrator_CreateOrGet(device)
   guard let calibrator = calibrator else {
       throw FlutterError(code: "NULL_HANDLE", message: "clCNFBCalibrator_CreateOrGet returned nil", details: nil)
   }
   ```

2. **Handle nil `msg` in error callback** (Task 2, `registerCallbacks`)

   The `clCNFB_ErrorHandler` callback signature is `(clCNFB, const char*)` — the message pointer can be nil. The existing `DeviceBridge` handles this with `msg.map { String(cString: $0) } ?? ""`. The plan should match this pattern instead of calling `String(cString:)` unconditionally, which would crash on nil.

3. **Note Float vs Double casting for calibration data** (Task 2, `createCalibrated`)

   Dart sends all numeric values as `double` (64-bit) over the platform channel. The `clCIndividualNFBData` C struct uses `float` (32-bit) fields. The implementer needs to cast: `Float(truncating: value as! NSNumber)` or similar. This is a standard pattern but worth noting explicitly since the plan lists the field types as "Float" without mentioning the incoming channel type mismatch.

## Positive Notes

- Plan correctly follows every established pattern from `DeviceBridge` — static weak `activeBridge`, `DeviceStreamHandler` reuse, `allStreamHandlers()` return convention, `checkCError` for SDK error handling, and the `do/catch` dispatch pattern in the plugin.
- Task 1 (visibility changes) is the right approach — lifting `DeviceStreamHandler` and `requireDevice()` to internal access is the minimal change needed, avoids duplication, and sets precedent for all future classifier bridges.
- Event channel IDs (`neiry_kit/events/nfbState`, `neiry_kit/events/nfbError`) match the Dart constants in `NeiryEvents` exactly.
- The plan correctly identifies that there is no `clCNFB_Destroy` — dispose only unregisters callbacks and clears the handle, which matches SDK behavior.
- C struct field mapping for `clCNFB_UserState` is verified correct against the SDK header (`timestampMilli`, `delta`, `theta`, `alpha`, `smr`, `beta`).
- `createCalibrated` flow (get calibrator → optionally import data → create) correctly mirrors the SDK's intended usage pattern.

PLAN_REVIEW_PASS
