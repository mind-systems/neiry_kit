# Code Review: CardioBridge

**Plan file:** `.ai-factory/plans/26-cardiobridge.md`
**Files reviewed:** `ios/Classes/classifiers/CardioBridge.swift` (new, 147 lines), `ios/Classes/NeiryKitPlugin.swift` (modified, 6 integration points)
**Cross-referenced:** `CCardio.h`, `CPPGTimedData.h`, `NfbBridge.swift`, `PhysioBridge.swift`, `EmotionsBridge.swift`, `DeviceBridge.swift` (DeviceStreamHandler), `cardio_classifier.dart`, `cardio_data.dart`, `ppg_data.dart`, `channel_names.dart`

## Critical Issues

None.

## Bugs

### 1. Missing nil guard on `ppgData` in PPG callback

**File:** `ios/Classes/classifiers/CardioBridge.swift:111–126`

The PPG callback does not guard `ppgData` for nil before passing it to `clCPPGTimedData_GetCount`:

```swift
clCCardio_SetOnPPGDataEvent(cardio, { _, ppgData in
    guard let bridge = CardioBridge.activeBridge else { return }
    let count = clCPPGTimedData_GetCount(ppgData)  // ← ppgData is OpaquePointer?, not unwrapped
```

The C callback typedef is `void (*)(clCCardio, clCPPGTimedData)` — Swift imports both parameters as `OpaquePointer?` in closure context. If the SDK ever passes nil for `ppgData`, `clCPPGTimedData_GetCount(ppgData)` will trap at runtime (implicitly unwrapped nil `OpaquePointer`).

The IndexesUpdate callback (line 92–94) correctly guards its data pointer:
```swift
guard let bridge = CardioBridge.activeBridge,
      let data = data else { return }
```

**Fix:** Add `let ppgData = ppgData` to the existing guard:

```swift
clCCardio_SetOnPPGDataEvent(cardio, { _, ppgData in
    guard let bridge = CardioBridge.activeBridge,
          let ppgData = ppgData else { return }
```

## Suggestions

None.

## Verification Summary

### C API alignment ✅
- `clCCardio_Create(device, &error)` — matches `CCardio.h:27`. Return type `clCCardio` assigned to `OpaquePointer?`.
- `clCCardio_CreateCalibrated(device, calibrator, &error)` — matches `CCardio.h:28`.
- `clCCardio_SetOnIndexesUpdateEvent` — callback `(clCCardio, const clCCardio_Data*)` matches `CCardio.h:30`. All 8 struct fields read correctly via `.pointee`.
- `clCCardio_SetOnPPGDataEvent` — callback `(clCCardio, clCPPGTimedData)` matches `CCardio.h:36`. Accessor pattern (`GetCount`, `GetValue`, `GetTimestampMilli`) matches `CPPGTimedData.h`.
- `clCCardio_SetOnCalibratedEvent` — callback `(clCCardio)` matches `CCardio.h:33`. Correctly emits empty map (no data payload).
- All three `SetOn*Event` functions take `clCError*` — all three wrapped with `var e = clCError()` + `try checkCError(e)`.
- No `clCCardio_Destroy` in the SDK — `dispose()` correctly does callback-only cleanup.

### Dart API alignment ✅
- Event channel IDs: `cardioData`, `ppgData`, `cardioCalibratedEvent` — match `NeiryEvents` constants exactly.
- MethodChannel ID: `neiry_kit/cardio` — matches `NeiryChannels.cardio`.
- Method names: `create`, `createCalibrated`, `dispose` — match `ClassifierMethods` constants.
- CardioData map keys: `ts`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable` — match `CardioData.fromMap` exactly.
- PpgData map keys: `sampleCount`, `values`, `timestamps` — match `PpgData.fromMap` exactly.
- Calibrated event: empty map `[:]` — Dart side maps to void via `.map((_) {})`.
- Type compatibility: Swift `Float` → Dart `double` (codec preserves via `num.toDouble()`), Swift `Int64` → Dart `int`, Swift `Bool` → Dart `bool`, Swift `UInt64` → Dart `int` (within safe range for timestamps).

### Bridge pattern alignment ✅
- Hybrid pattern (NfbBridge two-factory + PhysioBridge throwing `registerCallbacks`) — correct for Cardio.
- `static weak var activeBridge` — matches all existing bridges.
- `DeviceStreamHandler` for all three event channels — thread-safe `send()` dispatches to main thread.
- `unregisterCallbacks()` passes `nil` + reuses `var e` + `===` check — matches PhysioBridge exactly.
- `createCalibrated` calibration data import — mirrors NfbBridge field-by-field.

### Plugin integration (NeiryKitPlugin.swift) ✅
All six touch points verified:
1. Property `cardioBridge` declared at line 16 — correct position.
2. Instantiated at line 32 before `registerEventChannels()` — correct order.
3. Method dispatch at line 72 — `channelId == "neiry_kit/cardio"` → `handleCardioCall` — correct.
4. `handleCardioCall` (lines 485–519) — follows `handleNfbCall` pattern exactly with `create`, `createCalibrated`, `dispose` cases and standard `do/catch` error wrapping.
5. `cardioHandlers` lookup dictionary (lines 566–572) inserted after `physioHandlers`, used at line 619 before `StubStreamHandler` fallback — correct cascade position.
6. Dispose chain at line 145 — `cardioBridge?.dispose()` before other classifier disposals — correct order.

### Scope correctness ✅
- `memsData` channel remains on `StubStreamHandler` — correct (Cardio C API has no MEMS callback).
- No error stream — correct (`CCardio.h` has no `SetOnErrorEvent`).

REVIEW_PASS
