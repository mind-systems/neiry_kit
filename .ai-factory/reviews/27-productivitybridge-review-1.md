## Code Review Summary

**Plan:** `27-productivitybridge.md`
**Files Changed:** `ios/Classes/classifiers/ProductivityBridge.swift` (new), `ios/Classes/NeiryKitPlugin.swift` (modified), `lib/src/api/classifiers/productivity_classifier.dart` (modified)
**Risk Level:** 🟢 Low

### Verification

**Dart-side fix (Task 1):**
- `_individualNfbStream` changed from `Stream<NfbUserState>` with `NfbUserState.fromMap` decoder to `Stream<void>` with `.map((_) {})` — matches PhysioBridge/PhysioClassifier pattern exactly. ✓
- Public getter return type changed to `Stream<void>`. ✓
- Doc comment updated. ✓
- Unused `nfb_user_state.dart` import removed. No other reference to `NfbUserState` remains in the file. ✓

**ProductivityBridge.swift (Tasks 2–4):**

Verified all 5 callback signatures against `CProductivity.h`:
- `SetOnMetricsUpdateEvent(clCProductivity, handler)` — no `clCError*`. ✓
- `SetOnIndexesUpdateEvent(clCProductivity, handler)` — no `clCError*`. ✓
- `SetOnBaselineUpdateEvent(clCProductivity, handler)` — no `clCError*`. ✓
- `SetOnCalibrationProgressUpdateEvent(clCProductivity, handler)` — no `clCError*`. ✓
- `SetOnIndividualNFBUpdateEvent(clCProductivity, handler)` — no `clCError*`, single-param handler `(clCProductivity)`. ✓

`registerCallbacks()` correctly uses trailing-closure syntax (EmotionsBridge pattern) without `try`/`checkCError`. ✓

Verified all struct field mappings against `CProductivity.h`:
- **Metrics** — 10 float fields, `fatigueGrowthRate` (enum `.rawValue` → Int), `ts` (Int64), `artifactsData` (conditional `FlutterStandardTypedData` / `NSNull`). All names match C struct exactly. ✓
- **Indexes** — `ts`, `relaxation` (.rawValue), `stress` (.rawValue), `hasArtifacts` (Bool), 6 float baselines. All match. ✓
- **Baselines** — `ts`, 6 float fields. All match. Dual-emit to `baselinesHandler` (parsed map) and `calibratedHandler` (raw bytes) is correct. ✓
- **CalibrationProgress** — `Float` clamped to 0–1. ✓
- **IndividualNFB** — empty map `[:]`, single-param closure `{ _ in }`. ✓

Verified Dart model `fromMap()` compatibility:
- `ProductivityMetrics.fromMap`: `map['ts'] as int` ← Swift `Int64` ✓, `map['fatigueGrowthRate'] as int` ← Swift `UInt32` raw value ✓, `orNull(map[...])` handles sentinel `-1` floats ✓, `map['artifactsData'] as Uint8List` ← `FlutterStandardTypedData` ✓, null case ← `NSNull()` ✓
- `ProductivityIndexes.fromMap`: enum raw values as int ✓, bool ✓, float baselines via `orNull` ✓
- `ProductivityBaselines.fromMap`: all fields match ✓

Verified C API function signatures:
- `clCProductivity_Create(device, &error)` — returns handle, takes `clCError*`. ✓
- `clCProductivity_CreateWithIndividualData(device, &data, &error)` — takes `const clCIndividualNFBData*` directly (not calibrator handle). ✓
- `clCProductivity_ImportBaselines(productivity, &baselines, &error)` — takes `clCError*`. ✓
- `clCProductivity_ResetAccumulatedFatigue(productivity, &error)` — takes `clCError*`. ✓
- `clCProductivity_StartBaselineCalibration(productivity)` — NO `clCError*`. ✓

`importBaselines` round-trip: export serializes `clCProductivity_Baselines` via `withUnsafePointer` + `MemoryLayout.size`; import validates `data.count == MemoryLayout.size` then loads via `withUnsafeBytes`. Consistent size on same architecture. ✓

`clCIndividualNFBData` field mapping in `createCalibrated`: 8 float fields + `ts` (Int64) + `failReason` (enum). All match `CNFBCalibrator.h` struct definition and CardioBridge's identical mapping. ✓

**NeiryKitPlugin.swift (Task 5):**

- Property `productivityBridge` declared at line 17. ✓
- Initialized at line 34, after `cardioBridge`, before `registerEventChannels()`. ✓
- Method dispatch at line 76–77 routes `"neiry_kit/productivity"` → `handleProductivityCall`. ✓
- `handleProductivityCall` (lines 528–596): all 6 methods routed, `createCalibrated` has required `calibrationData` guard (unlike Cardio which is optional). ✓
- EventChannel handler dict built at lines 651–657, inserted in resolution chain at line 706 before `StubStreamHandler` fallback. ✓
- Dispose chain at line 150 calls `productivityBridge?.dispose()` before `bridge.dispose()`. ✓

All 6 ProductivityBridge stream handler channel IDs match `NeiryEvents` constants in `channel_names.dart` and the EventChannel registration list. The 7th productivity channel (`productivityError`) correctly falls through to `StubStreamHandler` since the C API has no error callback for Productivity. ✓

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- The implementation correctly distinguishes Productivity from Cardio on the `createCalibrated` path: Productivity passes `clCIndividualNFBData` directly to `CreateWithIndividualData`, while Cardio goes through `clCNFBCalibrator_CreateOrGet`. The `guard let` on `calibrationData` in the plugin dispatch prevents a zeroed struct from silently defeating calibration.
- The dual-emit from `SetOnBaselineUpdateEvent` cleanly serves both Dart streams (parsed `ProductivityBaselines` + opaque `Uint8List` blob for persistence) from a single C callback.
- Callback registration correctly follows the EmotionsBridge pattern (trailing closures, non-throwing) rather than cargo-culting the PhysioBridge/CardioBridge pattern (explicit closure arg, `clCError*`, throwing). This matches the C header where none of the Productivity `SetOn*Event` functions take an error parameter.
- The Dart-side `individualNfbStream` fix prevents a runtime `TypeError` that would have crashed the moment the C SDK fired the `IndividualNFBUpdate` callback.

REVIEW_PASS
