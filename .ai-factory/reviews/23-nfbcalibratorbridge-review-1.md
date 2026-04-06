# Code Review: NfbCalibratorBridge (iOS)

**Plan:** `.ai-factory/plans/23-nfbcalibratorbridge.md`
**Files reviewed:** `ios/Classes/NfbCalibratorBridge.swift` (new, 202 lines), `ios/Classes/NeiryKitPlugin.swift` (modified, +78 lines)
**Cross-referenced:** `DeviceBridge.swift`, `classifiers/NfbBridge.swift`, `DeviceLocatorBridge.swift` (checkCError), `lib/src/api/nfb_calibrator.dart`, `lib/src/models/individual_nfb_data.dart`, `lib/src/models/calibration_event.dart`, `lib/src/models/calibration_stage.dart`, `lib/src/channel/channel_names.dart`

## Critical Issues

*None.*

## Suggestions

*None — the implementation is clean and matches the plan precisely.*

## Verification

### Contract alignment (Dart ↔ Swift)

- **MethodChannel ID:** `"neiry_kit/nfb_calibrator"` matches `NeiryChannels.nfbCalibrator` ✅
- **EventChannel ID:** `"neiry_kit/events/nfbCalibration"` matches `NeiryEvents.nfbCalibration` ✅
- **Method names:** `startCalibration`, `stopCalibration`, `importCalibration`, `getCalibration`, `isCalibrated` — all match `NFBCalibratorMethods` constants ✅
- **Argument key:** `"calibratorData"` matches `NeiryArgs.calibratorData` ✅
- **Quick mode detection:** `args?["calibratorData"] as? String == "quick"` matches Dart `{NeiryArgs.calibratorData: 'quick'}` ✅
- **Import data shape:** `args["calibratorData"] as? [String: Any]` matches Dart `{NeiryArgs.calibratorData: data.toMap()}` ✅

### Event data shapes

- **Stage event:** `["type": "stage", "stage": Int]` — `CalibrationEvent.deserialize` reads `map['type'] as String` → `'stage'`, then `CalibrationStage.fromCode(map['stage'] as int)`. Bridge emits 0-indexed `currentStage` (0–3), matching `CalibrationStage` codes (stage1=0, stage2=1, stage3=2, stage4=3). ✅
- **Done event:** `["type": "done", "data": [String: Any]]` — deserializer reads `map['data'] as Map<Object?, Object?>` and passes to `IndividualNfbData.fromMap`. ✅
- **NFB data map keys:** `ts` (Int64), `failReason` (Int), plus 8 Float fields — all 10 keys match `IndividualNfbData.fromMap` expectations. Dart casts floats as `num` via `.toDouble()`, compatible with Swift `Float` through platform channel. ✅

### Stage advancement logic

Walked through the full 4-stage sequence:

1. `startCalibration(quick: false)` → starts `clCIndividualNFBCalibrationStage_1` (rawValue 0), `currentStage = 0`
2. Stage-finished callback: emits `stage: 0` → Dart `stage1`; increments to 1; starts stage rawValue 1 = `_2`
3. Stage-finished callback: emits `stage: 1` → Dart `stage2`; increments to 2; starts stage rawValue 2 = `_3`
4. Stage-finished callback: emits `stage: 2` → Dart `stage3`; increments to 3; starts stage rawValue 3 = `_4`
5. Stage-finished callback: emits `stage: 3` → Dart `stage4`; increments to 4; `>= 4` → waits
6. `onCalibrated` fires → emits `done` with data map

Result: 4 `CalibrationStageFinished` events (stage1–stage4) followed by 1 `CalibrationCompleted`. Matches Dart API doc: "up to four CalibrationStageFinished events followed by a single CalibrationCompleted event." ✅

### Quick mode path

`startCalibration(quick: true)` → `isQuickMode = true` → stage-finished callback returns early (no stage events) → `onCalibrated` fires → emits `done` on EventChannel → Dart `calibrateIndividualQuick()` completer resolves via `CalibrationCompleted`. ✅

### Review 2 critical fix — `getCalibration` isCalibrated guard

`getCalibration(device:)` at line 112: `guard clCNFBCalibrator_IsCalibrated(cal) else { return nil }`. Returns `nil` when uncalibrated. Dart side (`nfb_calibrator.dart:262–265`) checks `result != null` and returns `null` to caller — no `PlatformException` risk, no zero-struct leak. ✅

### Pattern consistency with existing bridges

- `activeBridge` static weak reference — same as `DeviceBridge`, `NfbBridge` ✅
- `DeviceStreamHandler` reuse for thread-safe dispatch — same as all other bridges ✅
- `checkCError` for C API calls with `clCError*` — same pattern ✅
- `FlutterError(code: "NULL_HANDLE")` for nil handles — same as `NfbBridge.createCalibrated` ✅
- `unregisterCallbacks` clears `activeBridge` only if `self === activeBridge` — same as `DeviceBridge`, `NfbBridge` ✅
- Float fields serialized as-is (no explicit Double cast) — same as `NfbBridge` lines 93–100 ✅
- Field-by-field `clCIndividualNFBData` deserialization — identical to `NfbBridge.createCalibrated` lines 51–65 ✅

### Plugin integration

- Instantiation order: after `nfbBridge`, before `registerEventChannels()` ✅
- Event channel registration: `nfbCalibratorHandlers` lookup merged into the handler chain ✅
- Dispose order: `nfbCalibratorBridge?.stopCalibration()` → `nfbBridge?.dispose()` → locator dispose → device release. Calibration stopped before classifier and device teardown ✅
- Error handling: all throwing methods wrapped in `do/catch` with `FlutterError`/unknown fallback ✅

### Thread safety

C callbacks access `bridge.isQuickMode`, `bridge.currentStage`, `bridge.calibrator` without synchronization. This matches the established pattern in `DeviceBridge` and `NfbBridge` — the SDK fires callbacks on a single background thread, and `DeviceStreamHandler.send()` dispatches to main thread for EventChannel delivery. ✅

REVIEW_PASS
