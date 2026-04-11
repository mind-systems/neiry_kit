# Plan Review: ProductivityBridge (Android JNI + Kotlin)

**Plan file:** `.ai-factory/plans/39-productivitybridge.md`
**Files Reviewed:** 15+ (plan, SDK header, existing JNI bridges, Kotlin bridges, iOS ProductivityBridge, Dart API, channel names, plugin wiring)
**Risk Level:** 🔴 High

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan follows the established layered bridge pattern (JNI C++ → Kotlin bridge → plugin wiring). All event channels and method dispatch align with architecture rules. No cross-bridge calls.
- **RULES.md:** Not present. `WARN` — no explicit convention violations detected.
- **ROADMAP.md:** `WARN` — The roadmap entry says "bridge deserializes Dart map (6 keys: `ts/gravity/...`) to C struct" for `ImportBaselines`, but the current Dart API sends `Uint8List` (raw bytes), not a structured map. This inconsistency between the roadmap vision and the current Dart API is the source of the critical issue below.

## Critical Issues

### 1. `importBaselines` data type mismatch — will crash at runtime

**Tasks affected:** Task 4 (JNI), Task 9 (NativeBridge.kt), Task 10 (ProductivityBridge.kt), Task 11 (plugin wiring)

The plan designs `importBaselines` as a structured-fields path — the JNI function receives individual fields (`jlong ts, jfloat gravity, jfloat productivity, ...`), the Kotlin bridge unpacks a `Map<String, Any>`, and the plugin casts the argument to `Map<String, Any>`.

**But the current Dart API sends `Uint8List` (raw bytes):**

```dart
// lib/src/api/classifiers/productivity_classifier.dart, line 254–262
Future<void> importBaselines(Uint8List data) async {
    await _channel.invokeMethod<void>(
      ClassifierMethods.importBaselines,
      {NeiryArgs.serial: _serial, NeiryArgs.baselines: data}, // data is Uint8List
    );
}
```

On Android, Flutter's standard codec delivers `Uint8List` as `byte[]`. Task 11's cast `(call.arguments as? Map<*, *>)?.get("baselines") as? Map<String, Any>` will return `null` (since `byte[]` is not `Map`), and the method will always fail with `"Missing 'baselines'"`.

**iOS matches the Dart API** — `ProductivityBridge.swift` receives `FlutterStandardTypedData` (raw bytes), does `data.data.withUnsafeBytes { $0.load(as: clCProductivity_Baselines.self) }`, and passes the struct to the C API. The Android bridge must do the same.

The `calibrated` stream already sends raw bytes on both iOS and in the plan (Task 7: `jbyteArray` under key `"baselines"`). The round-trip is: calibrated callback emits raw struct bytes → Dart receives `Uint8List` → Dart passes `Uint8List` back to `importBaselines` → native deserializes bytes to C struct. The plan breaks this round-trip at the import step.

**Fix:** Change `nativeImportProductivityBaselines` to accept `jbyteArray` instead of individual fields. In the Kotlin bridge, receive `ByteArray` from the plugin, pass it to JNI. In the JNI function, validate the byte array size matches `sizeof(clCProductivity_Baselines)`, then `GetByteArrayRegion` into the struct. This matches the iOS pattern exactly.

## Non-Critical Issues

### 2. "Six callbacks" count is inaccurate

Task 2 says "Register all six callbacks" but lists only five `SetOn*Event` calls. The SDK header (`CProductivity.h`) declares exactly five event registration functions:

- `clCProductivity_SetOnMetricsUpdateEvent`
- `clCProductivity_SetOnIndexesUpdateEvent`
- `clCProductivity_SetOnBaselineUpdateEvent`
- `clCProductivity_SetOnCalibrationProgressUpdateEvent`
- `clCProductivity_SetOnIndividualNFBUpdateEvent`

Task 7 correctly notes to check whether the error callback exists, but the count in Tasks 1–4 should be five, not six. The error callback does not exist in the SDK — there is no `clCProductivity_SetOnErrorEvent` in `CProductivity.h`.

### 3. Error handler wired but will never emit

The plan declares `g_productivityErrorSink` (Task 1), `nativeSetProductivityErrorSink` (Task 4/9), and includes `errorHandler` in `allStreamHandlers()` (Task 10). Since the SDK has no error callback, this sink will never receive events. The iOS bridge omits the error handler from `allStreamHandlers()` entirely (returns 6 handlers, not 7).

Not a bug (the `StubStreamHandler` fallback in the plugin already covers the `productivityError` channel), but it adds dead code. For consistency with iOS, consider omitting `errorHandler` from `allStreamHandlers()` and letting the plugin's existing stub handle it.

### 4. Task 7 baseline callback dual-dispatch is under-specified

The `on_productivity_baseline_update` callback dispatches to **two** sinks from one callback (structured map to `g_productivityBaselinesSink`, raw bytes to `g_productivityCalibratedSink`). The plan mentions acquiring both sinks under the same mutex lock, which is correct. However, the implementation requires:

- Two `make_map` calls (one for each sink)
- Two `CallStaticVoidMethod` dispatches
- Cleanup of two maps, two sink refs, one handler ref, plus the `jbyteArray`
- Both sinks must be `NewLocalRef`'d under the same lock, checked independently

The plan should specify the dual-map creation and extended cleanup explicitly to avoid mistakes during implementation.

## Positive Notes

- Correctly identifies that all `clCProductivity_SetOn*Event` functions take no `clCError*` — the critical difference from Physio (which takes `clCError*` on all event registrations). This was a past source of bugs.
- Correctly uses `clCProductivity_CreateWithIndividualData(dev, &data, &error)` directly, without going through `clCNFBCalibrator_CreateOrGet` — unlike Cardio/NFB which need the calibrator intermediary.
- `resetAccumulatedFatigue` and `importBaselines` error handling correctly wraps `clCError*`.
- All metrics/indexes/baselines map keys match the Dart `fromMap` factories exactly (verified key-by-key against `ProductivityMetrics.fromMap`, `ProductivityIndexes.fromMap`, `ProductivityBaselines.fromMap`).
- Thread-safety patterns (mutex, `NewLocalRef` under lock, `AttachCurrentThread`/`DetachCurrentThread`, `goto cleanup`) follow established conventions from `jni_physio.cpp` and `jni_cardio.cpp`.
- The two-commit plan is well-scoped: JNI layer first, then Kotlin wiring.
- Task dependencies are correct and well-ordered.
