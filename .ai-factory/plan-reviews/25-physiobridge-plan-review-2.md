## Plan Review: PhysioBridge (Round 2)

**Plan file:** `.ai-factory/plans/25-physiobridge.md`
**Files reviewed:** Plan + 12 codebase files (NfbBridge.swift, EmotionsBridge.swift, NeiryKitPlugin.swift, DeviceBridge.swift, DeviceLocatorBridge.swift, physio_classifier.dart, channel_names.dart, physio_states.dart, physio_baselines.dart, nfb_user_state.dart, explore notes, previous plan review)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** Plan follows the established bridge pattern (static weak `activeBridge`, `DeviceStreamHandler`, one bridge per C module, `allStreamHandlers()` for registration). No boundary violations. ✓
- **RULES.md:** File not present. WARN — skipped.
- **ROADMAP.md:** Plan targets the unchecked `PhysioBridge` iOS milestone. Aligned. ✓

### Previous Review Issues — Verification

All 4 issues from review 1 have been resolved:

1. **`registerCallbacks()` error handling** — Fixed. Now correctly shows `private func registerCallbacks() throws` with per-call `var error = clCError()` + `try checkCError(error)` at the registration call site. The conflated "expand manually" instruction is gone.
2. **`unregisterCallbacks()` missing `&error`** — Fixed. Now shows full code with 3-parameter `(handle, nil, &e)` form and throwaway `var e` variable.
3. **`importBaselines` numeric cast** — Was already correct per review 1's own analysis. No change needed.
4. **Trailing closure warning** — Fixed. Plan now explicitly warns "Do NOT copy the trailing-closure style" and explains why (3rd `&error` param prevents trailing closure syntax).

### Issues

#### 1. `startBaselineCalibration()` and `importBaselines(map:)` lack a guard on the `physio` handle

Both methods call C functions with `self.physio` directly:

- `clCPhysiologicalStates_StartBaselineCalibration(physio)`
- `clCPhysiologicalStates_ImportBaselines(physio, &baselines)`

If `physio` is nil — because `create()` hasn't been called, `create()` failed, or `dispose()` was called — these pass nil to C functions, which is undefined behavior and will likely crash.

The existing codebase guards handles defensively: `DeviceBridge.requireDevice()` throws `FlutterError(code: "NO_DEVICE")` when the device handle is nil. `registerCallbacks()` and `unregisterCallbacks()` both `guard let physio = physio` before using it.

**Fix:** Add a guard at the top of both methods. Either:

(a) Add a `requirePhysio()` helper (mirrors `DeviceBridge.requireDevice()`):
```swift
private func requirePhysio() throws -> OpaquePointer {
    guard let physio = physio else {
        throw FlutterError(code: "NOT_CREATED",
                           message: "PhysioBridge not created — call create first",
                           details: nil)
    }
    return physio
}
```

Then `startBaselineCalibration()` and `importBaselines(map:)` become `throws`, and the plugin dispatch wraps them in `do/catch`.

(b) Or add inline `guard let physio = physio else { return }` if silent no-op is acceptable (less safe — callers won't know it failed).

Option (a) is preferred because it surfaces the error to Dart. This also means Task 2's dispatch cases for `"startBaselineCalibration"` and `"importBaselines"` need `do/catch` wrappers (the plan currently says "No `do/catch` needed" for startBaselineCalibration).

### Positive Notes

- All 4 EventChannel IDs match `channel_names.dart` constants exactly and are already registered in `NeiryKitPlugin.registerEventChannels()`.
- The `clCError*` asymmetry (Physio registration functions take it, Emotions don't) is correctly handled — registration calls use `try checkCError`, while `StartBaselineCalibration` and `ImportBaselines` correctly skip it.
- The `IndividualNFBUpdateHandler` empty-signal pattern (`[:]` → Dart `Stream<void>`) correctly fixes the `NfbUserState.fromMap` crash on empty maps.
- Baselines struct field names (`ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`) match both the C struct and the Dart `PhysiologicalStatesBaselines.fromMap`/`toMap` keys.
- `PhysiologicalStatesValue` serialization includes all 8 fields (6 floats + 2 bools), matching the Dart model's `fromMap` expectations.
- Calibration progress clamping (`max(0.0, min(1.0, progress))`) is good defensive coding for an undocumented range.
- Cleanup ordering in `handleDeviceLocatorCall.dispose` (classifiers → locator → device) is correct.
- The `activeBridge` static-weak-reference pattern and `unregisterCallbacks` cleanup are consistent with NfbBridge and EmotionsBridge.
- Task 3's `NfbUserState` import removal is safe — no other references remain in the file after the stream type change.
