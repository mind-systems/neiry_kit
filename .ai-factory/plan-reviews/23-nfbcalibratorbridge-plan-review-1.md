# Plan Review: NfbCalibratorBridge (iOS)

**Plan file:** `.ai-factory/plans/23-nfbcalibratorbridge.md`
**Files Reviewed:** 7 plan tasks across 3 phases
**Risk Level:** 🔴 High

## Context Gates

- **ARCHITECTURE.md** — `WARN`: no violations. File placement (`ios/Classes/NfbCalibratorBridge.swift`, not inside `classifiers/`), dependency rules, and bridge-per-module principle all align.
- **RULES.md** — not present (WARN, non-blocking).
- **ROADMAP.md** — `WARN`: the plan aligns with the `NfbCalibratorBridge` milestone item. No linkage issues.

## Critical Issues

### 1. Quick-mode data delivery is incompatible with the Dart API

**Tasks 3, 4, 5 — `pendingResult` / `isQuickMode` mechanism**

The plan says:

- Task 3 step 6: for quick mode, store `result` in `pendingResult` and do NOT call `result(nil)`.
- Task 4 `onCalibrated`: if `isQuickMode && pendingResult != nil`, call `pendingResult!(dataMap)` and do NOT emit on EventChannel.
- Task 5 `stopCalibration`: if `pendingResult` is non-nil, call `pendingResult!(nil)`.

This is **wrong**. The Dart `calibrateIndividualQuick()` (`lib/src/api/nfb_calibrator.dart:181–246`) works like this:

1. Opens `_calibrationEventChannel.receiveBroadcastStream()` (line 191).
2. Listens on that EventChannel for a `CalibrationCompleted` event (lines 204–213).
3. Invokes `startCalibration` as `invokeMethod<void>` (line 237) — the return type is `void`, meaning the MethodChannel result value is discarded.
4. The `Completer<IndividualNfbData>` is resolved from the EventChannel listener, not from the MethodChannel result.

If the native bridge delivers quick-mode data via `pendingResult!(dataMap)` and skips the EventChannel, the Dart EventChannel listener never receives `CalibrationCompleted`, and the returned `Future<IndividualNfbData>` hangs forever.

**Fix:** The bridge must emit `{'type': 'done', 'data': dataMap}` on the EventChannel for **both** full and quick mode. The MethodChannel `result` should be called with `result(nil)` immediately (same as full mode). The `pendingResult` field, `isQuickMode` flag, and all the conditional quick-mode logic in `onCalibrated` and `stopCalibration` can be removed entirely — the native bridge does not need to distinguish between the two modes at all. The Dart layer already handles the difference (stream vs. completer consuming the same EventChannel).

This simplifies Tasks 3, 4, and 5 significantly:
- `startCalibration` always: create/get calibrator → register callbacks → call either `CalibrateIndividualNFB(stage_1)` or `CalibrateIndividualNFBQuick` based on the `quick` flag → call `result(nil)`.
- `onCalibrated` callback always emits `{'type': 'done', 'data': dataMap}` on EventChannel.
- `stopCalibration` simply unregisters callbacks and resets `currentStage`.

The bridge still needs to know whether it's in quick mode for one reason: the stage-finished callback must not advance stages during quick calibration. A boolean `isQuickMode` for that guard alone is valid — but it should not gate EventChannel emission.

## Suggestions

### 1. Float-to-Double casts are inconsistent with existing bridges

Task 4 says "Cast all `Float` fields to `Double` for Dart compatibility." However, `NfbBridge` (`ios/Classes/classifiers/NfbBridge.swift:93–100`) serializes C `Float` values directly into the map without casting:

```swift
"delta": state.delta,  // Float, not explicitly cast to Double
```

Flutter's standard message codec handles `Float` correctly — Dart receives it as `double`. Explicitly casting adds noise and deviates from the established pattern. Remove the "cast to `Double`" instruction and serialize `Float` values as-is for consistency.

### 2. Stage event value in exploration notes vs. plan

The exploration notes (`08-explore-nfb-calibrator.md`, line 58) show `emit {'type':'stage','stage':1}` for stage_1 completion. The plan correctly uses 0-indexed `currentStage` (emitting 0 when stage_1 finishes, matching `CalibrationStage.fromCode(0)` = `stage1`). The notes are wrong, not the plan — but the discrepancy should be fixed in the notes to prevent confusion during implementation.

### 3. Missing guard for callback-thread re-entrancy on stage advancement

Task 4 calls `clCNFBCalibrator_CalibrateIndividualNFB` for the next stage directly inside the `onStageFinished` C callback. This should be safe (SDK is designed for it), but add a brief comment in the implementation noting that re-entering the SDK from its own callback is intentional and verified against the SDK's threading model.

## Positive Notes

- File placement at `ios/Classes/NfbCalibratorBridge.swift` (not inside `classifiers/`) correctly follows ARCHITECTURE.md — the calibrator is a separate C module, not a classifier.
- The static `activeBridge` weak reference pattern matches `NfbBridge` and `DeviceBridge` exactly.
- Correct identification that `clCNFBCalibrator_CreateOrGet` takes no `clCError*` and `IsCalibrated` returns a bare `bool` — error-handling boundaries match the C API precisely.
- Cleanup in the dispose path (Task 7) is correctly placed before `nfbBridge?.dispose()`, ensuring in-progress calibration is stopped before classifiers and device are torn down.
- The plan correctly reuses `DeviceStreamHandler` rather than implementing a custom `FlutterStreamHandler`, keeping the codebase DRY.
- The `onCalibrated` event correctly wraps data inside a `'data'` key (`{'type': 'done', 'data': dataMap}`) matching `CalibrationEvent.deserialize` which reads `map['data'] as Map`.
- Stage advancement logic (emit current → increment → call next if < 4) is correct and produces the right 0-indexed values for `CalibrationStage.fromCode`.
