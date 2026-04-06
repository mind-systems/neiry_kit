# Plan Review: NfbCalibratorBridge (iOS) — Review 2

**Plan file:** `.ai-factory/plans/23-nfbcalibratorbridge.md`
**Files Reviewed:** 7 plan tasks across 3 phases, verified against 8 codebase files
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md** — `WARN`: no violations. File placement (`ios/Classes/NfbCalibratorBridge.swift`), dependency rules, bridge-per-module principle, and `DeviceStreamHandler` reuse all align.
- **RULES.md** — not present (`WARN`, non-blocking).
- **ROADMAP.md** — `WARN`: the ROADMAP entry for `NfbCalibratorBridge` still says "do NOT emit on EventChannel for quick mode." The plan correctly diverges from this — the Dart API uses the EventChannel for both modes (`nfb_calibrator.dart:191`). The ROADMAP bullet is stale and should be updated after this plan lands to avoid confusing the Android bridge implementer.

## Review of fixes from Review 1

All three issues from review 1 have been addressed:

1. **Quick-mode data delivery** — Fixed. The `pendingResult` mechanism is gone. Task 3 now calls `result(nil)` immediately for both modes. Task 4's `onCalibrated` callback emits on EventChannel for both modes, with explicit Dart-side references explaining why.
2. **Float-to-Double casting** — Fixed. Task 4 now says "Serialize `Float` fields directly without explicit `Double` casting" and cites the `NfbBridge` pattern as precedent.
3. **Re-entrancy comment** — Fixed. Task 4 includes the instruction to add a code comment about SDK re-entry from callbacks.

## Critical Issues

### 1. `getCalibration` returns data instead of `nil` when uncalibrated

**Task 6 — `getCalibration(device:)`**

The plan calls `clCNFBCalibrator_GetIndividualNFB(calibrator, &data, &error)` unconditionally and always returns the serialized map. Two problems:

1. **If the SDK errors when uncalibrated:** `checkCError` throws a `FlutterError`, which propagates to Dart as a `PlatformException`. But `NfbCalibrator.getCalibrationData()` (`nfb_calibrator.dart:272–277`) does not catch exceptions — it only checks if the result is `null`:
   ```dart
   final result = await _channel.invokeMethod<Map<Object?, Object?>>(
     NFBCalibratorMethods.getCalibration,
   );
   return result != null ? IndividualNfbData.fromMap(result) : null;
   ```
   The caller gets an unhandled `PlatformException` instead of the documented `null`.

2. **If the SDK returns a default/zero struct:** The bridge serializes it and returns a map, so the Dart side creates a non-null `IndividualNfbData` with default values. The API doc says it returns `null` "if no calibration has been performed or imported yet" — returning default data violates this contract.

**Fix:** Guard with `isCalibrated` before calling `GetIndividualNFB`:
```swift
func getCalibration(device: OpaquePointer) -> [String: Any]? {
    guard let calibrator = clCNFBCalibrator_CreateOrGet(device) else { return nil }
    guard clCNFBCalibrator_IsCalibrated(calibrator) else { return nil }
    var data = clCIndividualNFBData()
    var error = clCError()
    clCNFBCalibrator_GetIndividualNFB(calibrator, &data, &error)
    // checkCError...
    // serialize and return
}
```

Return `nil` when uncalibrated so the Dart side receives `null` from `invokeMethod` and returns `null` to the caller, matching the API contract.

## Suggestions

*None — the plan is clean after Review 1 fixes and the critical issue above.*

## Positive Notes

- All three Review 1 issues are correctly resolved. The quick-mode fix in particular is well-documented — Task 4's inline explanation with line-number references to the Dart code makes the reasoning transparent to the implementer.
- File placement, channel IDs, event data shapes, and C API calling conventions all match the codebase precisely.
- Stage advancement logic (emit `currentStage` → increment → call next if < 4) produces correct 0-indexed values for `CalibrationStage.fromCode`.
- The `onCalibrated` event correctly nests data under a `'data'` key matching `CalibrationEvent.deserialize(map['data'] as Map)`.
- Cleanup ordering in Task 7 (`stopCalibration` before `nfbBridge?.dispose()`) is correct — calibration callbacks are unregistered before the classifier and device are torn down.
- The `isQuickMode` flag is retained solely for its valid purpose (guarding stage advancement in the stage-finished callback) rather than gating EventChannel emission.
