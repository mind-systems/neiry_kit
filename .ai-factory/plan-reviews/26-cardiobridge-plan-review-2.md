# Plan Review: CardioBridge (Review 2)

**Plan file:** `.ai-factory/plans/26-cardiobridge.md`
**Files reviewed:** 14 (plan, C headers CCardio.h + CPPGTimedData.h, NfbBridge.swift, PhysioBridge.swift, EmotionsBridge.swift, NeiryKitPlugin.swift, DeviceBridge.swift, DeviceLocatorBridge.swift, cardio_classifier.dart, cardio_data.dart, ppg_data.dart, channel_names.dart, exploration notes 07, previous review)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** PASS — plan follows "one bridge class per C API module" principle, uses `DeviceStreamHandler` for thread-safe event dispatch, and integrates into `NeiryKitPlugin.swift` via the established lookup-dictionary pattern.
- **RULES.md:** File not present. `WARN` — non-blocking.
- **ROADMAP.md:** PASS — CardioBridge milestone is listed as unchecked under "iOS bridges". Plan scope matches. (Stale `cardioError` reference in roadmap noted in review 1 — the plan correctly omits it since neither the C API nor the Dart API expose it.)

## Previous Review Status

Review 1 had one suggestion: `registerCallbacks()` section said "Both" instead of "All three" and lacked explicit `clCError*` mention for the PPG callback. **Fixed** — the plan now correctly says "All three callbacks (`SetOnIndexesUpdateEvent`, `SetOnPPGDataEvent`, and `SetOnCalibratedEvent`)" and all three items include explicit `var e = clCError()` → register → `try checkCError(e)` instructions.

## Critical Issues

None.

## Suggestions

None.

## Verification Summary

### C API alignment ✅
- `clCCardio_Create(device, &error)` and `clCCardio_CreateCalibrated(device, calibrator, &error)` — confirmed in `CCardio.h`.
- All three `SetOn*Event` functions take `clCError*` — confirmed. Plan wraps each with error check.
- `clCCardio_Data` struct fields (`timestampMilli`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable`) — confirmed, direct struct access (no getters).
- PPG accessor functions (`GetCount`, `GetValue`, `GetTimestampMilli`) — confirmed in `CPPGTimedData.h`, no `clCError*` on accessors.
- No `clCCardio_Destroy` function — confirmed.

### Dart API alignment ✅
- Channel IDs: `neiry_kit/events/cardioData`, `neiry_kit/events/ppgData`, `neiry_kit/events/cardioCalibratedEvent` — match `NeiryEvents` constants and `NeiryKitPlugin.swift` registration list.
- MethodChannel: `neiry_kit/cardio` — matches `NeiryChannels.cardio`.
- Method names: `create`, `createCalibrated`, `dispose` — match `ClassifierMethods` constants.
- Map keys for `cardioData`: `ts`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable` — match `CardioData.fromMap` exactly.
- Map keys for `ppgData`: `sampleCount`, `values`, `timestamps` — match `PpgData.fromMap` exactly.
- Calibrated event emits `[:]` — Dart side maps to `void` via `.map((_) {})`.

### Bridge pattern alignment ✅
- Hybrid pattern (NfbBridge two-factory paths + PhysioBridge throwing `registerCallbacks`) — correct for Cardio since the C setters take `clCError*`.
- `static weak var activeBridge` pattern — matches all existing bridges.
- `DeviceStreamHandler` instances for all three event channels — correct.
- `unregisterCallbacks()` passes `nil` with local `clCError` + `===` check before clearing `activeBridge` — matches PhysioBridge.
- `dispose()` calls `unregisterCallbacks()` + sets handle to `nil`, no Destroy — correct.

### Plugin integration (Task 2) ✅
All six touch points in `NeiryKitPlugin.swift` covered:
1. Property declaration after `physioBridge` (line 15) — correct line reference.
2. Instantiation after `PhysioBridge()` and before `registerEventChannels()` — correct position.
3. Method dispatch branch `channelId == "neiry_kit/cardio"` replacing current fall-through — correct.
4. `handleCardioCall` dispatcher following `handleNfbCall` pattern with `create`, `createCalibrated`, `dispose` cases — correct.
5. Event channel lookup dictionary `cardioHandlers` inserted after `physioHandlers` and before `StubStreamHandler` fallback — correct.
6. Dispose chain: `cardioBridge?.dispose()` alongside other classifier disposals in `handleDeviceLocatorCall` `"dispose"` case — correct.

### Scope correctness ✅
- `memsData` channel (`neiry_kit/events/memsData`) remains on `StubStreamHandler` — correct, the C Cardio API has no MEMS callback and the Dart `CardioClassifier` doesn't expose a MEMS stream.
- No error stream — correct, `CCardio.h` has no `SetOnErrorEvent`.

## Positive Notes

- **Review 1 fix applied cleanly.** The `registerCallbacks()` section now explicitly covers all three callbacks with consistent error-handling instructions.
- **Thorough pattern references.** Each aspect names the exact bridge to follow (NfbBridge for factory paths, PhysioBridge for throwing callbacks), eliminating ambiguity.
- **Complete plugin integration.** All six wiring points in the dispatcher are specified with correct line numbers and insertion positions.
- **C API accuracy.** Every function name, struct field, and callback typedef matches the vendored headers exactly.

PLAN_REVIEW_PASS
