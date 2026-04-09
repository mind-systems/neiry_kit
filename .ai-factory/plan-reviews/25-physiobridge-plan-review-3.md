## Plan Review: PhysioBridge (Round 3)

**Plan file:** `.ai-factory/plans/25-physiobridge.md`
**Files reviewed:** Plan + 14 codebase files (NfbBridge.swift, EmotionsBridge.swift, NeiryKitPlugin.swift, DeviceBridge.swift/DeviceStreamHandler, physio_classifier.dart, channel_names.dart, physio_states.dart, physio_baselines.dart, nfb_user_state.dart, neiry_kit.dart barrel, explore notes, previous plan reviews 1 & 2)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** Plan follows all established patterns — static weak `activeBridge`, `DeviceStreamHandler` per event, one bridge per C module, `allStreamHandlers()` for registration, `requireX()` guard helper. No boundary violations. ✓
- **RULES.md:** File not present. WARN — skipped.
- **ROADMAP.md:** Plan targets the unchecked `PhysioBridge` iOS milestone. Aligned. ✓

### Previous Review Issues — Verification

**Review 1** (4 issues): All resolved in plan iteration 2.

**Review 2** (1 issue): `startBaselineCalibration()` and `importBaselines(map:)` lacked guards on the `physio` handle. **Now resolved:**
- `requirePhysio()` helper added (lines 68–78), mirrors `DeviceBridge.requireDevice()`.
- Both methods marked `throws` and guard with `let physio = try requirePhysio()` (lines 80, 82).
- Task 2 dispatch cases for both methods explicitly state "Wrap in `do/catch`" (lines 101–102).

### Verification Checklist

All critical details verified against the codebase:

- **EventChannel IDs:** All 4 handler IDs (`physiologicalState`, `physiologicalCalibrationProgress`, `physiologicalCalibrated`, `physiologicalIndividualNfb`) match `NeiryEvents` constants in `channel_names.dart` and are already registered in `NeiryKitPlugin.registerEventChannels()` (lines 471, 479–481). ✓
- **MethodChannel ID:** `"neiry_kit/physiological"` matches `NeiryChannels.physiological` and is already registered in `registerMethodChannels()` (line 40). ✓
- **C API signatures:** 3-parameter `SetOn*Event(handle, handler, &error)` form confirmed by explore notes. `StartBaselineCalibration` and `ImportBaselines` have no `clCError*` — confirmed. ✓
- **Callback data shapes:** `clCPhysiologicalStates_Value` (8 fields), `clCPhysiologicalStates_Baselines` (6 fields), calibration progress (bare float), individual NFB (handle-only) — all match explore notes and Dart models. ✓
- **Dart `importBaselines` argument path:** Dart sends `{serial: ..., baselines: baselines.toMap()}`. Plan extracts `args?["baselines"]`. Map keys (`ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`) match `PhysiologicalStatesBaselines.toMap()`. ✓
- **Trailing closure avoidance:** Plan explicitly warns against trailing-closure syntax for 3-parameter registration functions. ✓
- **`unregisterCallbacks()`:** Full code shown with 3-parameter `(handle, nil, &e)` form and throwaway `var e`. ✓
- **Cleanup ordering:** `physioBridge?.dispose()` inserted after `emotionsBridge?.dispose()` and before `nfbBridge?.dispose()` in `handleDeviceLocatorCall.dispose`. ✓
- **Task 3 type fix:** `Stream<NfbUserState>` → `Stream<void>` prevents `NfbUserState.fromMap` crash on empty map from `IndividualNFBUpdateHandler`. Uses direct `receiveBroadcastStream().map((_) {})` instead of `_eventStream` helper. `NfbUserState` import removal is safe — no other references in the file. ✓

### Positive Notes

- All issues from reviews 1 and 2 have been cleanly resolved. The plan has converged to a correct, implementable state.
- The `requirePhysio()` guard pattern correctly surfaces nil-handle errors to Dart via `FlutterError`, rather than silently passing nil to C functions (UB/crash).
- Calibration progress clamping is good defensive coding for an undocumented range.
- The plan is thorough about the PhysioStates vs Emotions API asymmetry (`clCError*` on registration) and provides concrete code examples to prevent implementer confusion.

PLAN_REVIEW_PASS
