# Code Review: ProductivityBridge (Android JNI + Kotlin)

**Plan file:** `.ai-factory/plans/39-productivitybridge.md`
**Files reviewed:** `jni_productivity.cpp`, `ProductivityBridge.kt`, `NativeBridge.kt`, `NeiryKitPlugin.kt`, `CMakeLists.txt`
**Cross-referenced against:** `CProductivity.h` (SDK header), `ProductivityBridge.swift` (iOS), Dart `productivity_classifier.dart` + model `fromMap` factories, `jni_physio.cpp`, `jni_cardio.cpp`

## Critical Issues

None.

## Non-Critical Issues

None.

## Verification Summary

### Plan review fixes applied correctly

1. **`importBaselines` raw bytes** — JNI accepts `jbyteArray`, validates `sizeof(clCProductivity_Baselines)`, copies via `GetByteArrayRegion`. Kotlin declares `ByteArray`. Plugin casts `as? ByteArray`. Matches Dart `Uint8List` → Android `byte[]` codec path and mirrors iOS `FlutterStandardTypedData` pattern. The round-trip (baseline callback → `jbyteArray` → Dart `Uint8List` → `importBaselines` → `jbyteArray` → C struct) is complete and correct.

2. **Five callbacks, not six** — All `SetOn*Event` registrations and unregistrations use exactly the five functions declared in `CProductivity.h`, all called without `clCError*` (fire-and-forget). Matches the SDK header.

3. **No error sink/handler** — `g_productivityErrorSink` removed from JNI. No `errorHandler` in `ProductivityBridge.kt`. `allStreamHandlers()` returns 6 pairs. `productivityError` channel falls through to `StubStreamHandler`. Matches iOS behavior.

4. **Dual-dispatch in baseline callback** — Three refs acquired under one mutex lock. Two maps built independently. `blob` (`jbyteArray`) created and put into `calibratedMap`. All six local refs cleaned up in `cleanup:`. Correct.

### JNI ↔ Kotlin parameter correspondence

All JNI function names follow the `Java_com_neiry_neiry_1kit_NativeBridge_<method>` convention (underscore encoded as `_1`). All Kotlin `external fun` declarations have matching JNI signatures (`Long`↔`jlong`, `Int`↔`jint`, `Float`↔`jfloat`, `ByteArray`↔`jbyteArray`).

### Map key accuracy (verified key-by-key against Dart `fromMap`)

- **ProductivityMetrics**: 12 keys (`ts`, `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`, `fatigueGrowthRate`) + optional `artifactsData` — all match `ProductivityMetrics.fromMap` and iOS emit.
- **ProductivityIndexes**: 10 keys (`ts`, `relaxation`, `stress`, `hasArtifacts`, `gravityBaseline`, `productivityBaseline`, `fatigueBaseline`, `reverseFatigueBaseline`, `relaxationBaseline`, `concentrationBaseline`) — all match `ProductivityIndexes.fromMap` and iOS emit.
- **ProductivityBaselines**: 7 keys (`ts`, `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration`) — all match `ProductivityBaselines.fromMap` and iOS emit.
- **Calibrated**: 1 key (`baselines` as raw `byte[]`) — matches Dart `map['baselines'] as Uint8List`.
- **CalibrationProgress**: 1 key (`progress`, clamped 0–1) — matches Dart and iOS.
- **IndividualNFB**: empty map — matches pattern.

### Event channel IDs

All 6 real channel IDs in `allStreamHandlers()` match Dart `NeiryEvents` constants and are present in the plugin's `eventChannelIds` list. The 7th (`productivityError`) is in `eventChannelIds` but not in `streamHandlerMap`, so it correctly falls through to `StubStreamHandler`.

### Thread safety

Mutex-guarded sink access, `NewLocalRef` under lock, `AttachCurrentThread`/`DetachCurrentThread` lifecycle — identical to `jni_physio.cpp` and `jni_cardio.cpp`.

### SDK API usage

- `clCProductivity_Create` / `clCProductivity_CreateWithIndividualData`: both check `clCError`. Productivity's `CreateWithIndividualData` takes `clCIndividualNFBData*` directly (no `clCNFBCalibrator_CreateOrGet` intermediary unlike Cardio). Correct per SDK header.
- `clCProductivity_ImportBaselines`: takes `clCError*` — checked. Correct.
- `clCProductivity_ResetAccumulatedFatigue`: takes `clCError*` — checked. Correct.
- `clCProductivity_StartBaselineCalibration`: void, no error — fire-and-forget. Correct.
- All five `SetOn*Event`: void, no `clCError*` — fire-and-forget. Correct (critical difference from Physio/Cardio which take `clCError*`).
- No `clCProductivity_Destroy` in SDK — dispose is callback-unregister + sink cleanup only. Confirmed correct.

### Plugin wiring

- `productivityBridge` instantiated in `onAttachedToEngine` after `cardioBridge`.
- Stream handlers registered via `allStreamHandlers()` loop.
- `handleProductivityCall` dispatches all 6 method names (`create`, `createCalibrated`, `startBaselineCalibration`, `importBaselines`, `resetAccumulatedFatigue`, `dispose`) with proper error handling (`FlutterError` + `Exception` catch).
- `onDetachedFromEngine` disposes productivity before cardio and nulls the reference.

### CMakeLists.txt

`jni_productivity.cpp` added after `jni_cardio.cpp` in the source list. Correct.

REVIEW_PASS
