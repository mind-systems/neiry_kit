# Plan: ProductivityBridge (Android JNI + Kotlin)

## Context
Implement the Android-side Productivity classifier bridge — JNI C++ layer (`jni_productivity.cpp`) and Kotlin bridge (`ProductivityBridge.kt`). Five SDK callbacks (metrics, indexes, baselines, calibration progress, individual NFB) plus a sixth `calibrated` sink derived from the baselines callback, two factory paths (plain + `CreateWithIndividualData` converting Dart map to `clCIndividualNFBData` struct), three command methods (`startBaselineCalibration`, `importBaselines` accepting raw bytes, `resetAccumulatedFatigue`), and plugin wiring. Replaces the current `handleProductivityCall` stub with real dispatch.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI C++ layer

- [x] **Task 1: Create `jni_productivity.cpp` with extern declarations and file-private state**
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Create the file with standard includes (`<jni.h>`, `<pthread.h>`, `<cstdio>`, `<cmath>`, `"CCapsuleAPI.h"`). Declare all extern symbols following the pattern from `jni_physio.cpp`:
  - From `jni_device_locator.cpp`: `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`
  - From `jni_device.cpp`: `make_map`, `map_put_float`, `map_put_long`, `map_put_int`, `map_put_bool`, `map_put_object`
  - From `jni_device_locator.cpp`: `throw_sdk_error`
  DO NOT redefine any of these — `extern` only.
  Declare file-private (`static`) state: six sinks (`g_productivityMetricsSink`, `g_productivityIndexesSink`, `g_productivityBaselinesSink`, `g_productivityCalibrationProgressSink`, `g_productivityCalibratedSink`, `g_productivityIndividualNfbSink`), one `pthread_mutex_t g_productivity_mutex = PTHREAD_MUTEX_INITIALIZER`.
  No error sink — the SDK has no error callback (`CProductivity.h` declares no `clCProductivity_SetOnErrorEvent`). The `productivityError` event channel is handled by `StubStreamHandler` on the plugin side.
  Forward-declare five static callback functions: `on_productivity_metrics_update`, `on_productivity_indexes_update`, `on_productivity_baseline_update`, `on_productivity_calibration_progress`, `on_productivity_individual_nfb_update`.

- [x] **Task 2: Implement `nativeCreateProductivity` (plain factory)** (depends on Task 1)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Inside `extern "C"` block, implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateProductivity(JNIEnv*, jobject, jlong deviceHandle)`:
  1. Cast `deviceHandle` to `clCDevice` via `(clCDevice)(uintptr_t)`.
  2. Call `clCProductivity_Create(dev, &error)` — on failure, `throw_sdk_error` and return 0.
  3. Register all five callbacks. **Critical difference from Physio/Cardio:** ALL `SetOn*Event` for Productivity take NO `clCError*` — call them fire-and-forget:
     - `clCProductivity_SetOnMetricsUpdateEvent(prod, on_productivity_metrics_update)`
     - `clCProductivity_SetOnIndexesUpdateEvent(prod, on_productivity_indexes_update)`
     - `clCProductivity_SetOnBaselineUpdateEvent(prod, on_productivity_baseline_update)`
     - `clCProductivity_SetOnCalibrationProgressUpdateEvent(prod, on_productivity_calibration_progress)`
     - `clCProductivity_SetOnIndividualNFBUpdateEvent(prod, on_productivity_individual_nfb_update)`
     No error checking after registration — these functions are void-returning without error params.
  4. Return `(jlong)(uintptr_t)prod`.

- [x] **Task 3: Implement `nativeCreateProductivityWithIndividualData` (calibrated factory)** (depends on Task 1)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateProductivityWithIndividualData(JNIEnv*, jobject, jlong deviceHandle, jlong ts, jint failReason, jfloat individualFrequency, jfloat individualPeakFrequency, jfloat individualPeakFrequencyPower, jfloat individualPeakFrequencySuppression, jfloat individualBandwidth, jfloat individualNormalizedPower, jfloat lowerFrequency, jfloat upperFrequency)`:
  1. Cast device handle.
  2. Populate `clCIndividualNFBData data = {}` with all 10 fields: `timestampMilli`, `failReason` (cast to `clCIndividualNFBCalibrationFailReason`), `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`.
  3. Call `clCProductivity_CreateWithIndividualData(dev, &data, &error)` — unlike Cardio which uses `clCNFBCalibrator_CreateOrGet` + `CreateCalibrated`, Productivity takes the struct pointer directly. Throw on failure.
  4. Register all five callbacks (same as Task 2 — no error params).
  5. Return handle as `jlong`.
  **No `hasCalibrationData` boolean param needed** — unlike Cardio/NFB calibrated factories, Productivity always receives the struct when this factory is called.

- [x] **Task 4: Implement sink setters, command methods, and dispose** (depends on Task 1)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Implement six sink-setter JNI functions following the `jni_physio.cpp` pattern (lock mutex, `DeleteGlobalRef` old sink, `NewGlobalRef` new sink):
  - `nativeSetProductivityMetricsSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetProductivityIndexesSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetProductivityBaselinesSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetProductivityCalibrationProgressSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetProductivityCalibratedSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetProductivityIndividualNfbSink(JNIEnv*, jobject, jobject sink)`
  No error sink setter — the SDK has no error callback.
  Implement `nativeStartProductivityBaselineCalibration(JNIEnv*, jobject, jlong prodHandle)`: guard `prodHandle == 0` → early return, then call `clCProductivity_StartBaselineCalibration(prod)` — no error param, fire-and-forget (same pattern as `nativeStartBaselineCalibration` in `jni_physio.cpp`).
  Implement `nativeImportProductivityBaselines(JNIEnv* env, jobject, jlong prodHandle, jbyteArray baselinesBytes)`: **accepts raw bytes, not individual fields** (matching the Dart API which sends `Uint8List` and the iOS pattern which receives `FlutterStandardTypedData`). Implementation:
  1. Guard `prodHandle == 0` → early return.
  2. Get byte array length via `env->GetArrayLength(baselinesBytes)`.
  3. Validate size equals `sizeof(clCProductivity_Baselines)` — if mismatch, throw `IllegalArgumentException("Baselines data size mismatch")` and return.
  4. Declare `clCProductivity_Baselines baselines = {}`.
  5. Copy bytes into struct: `env->GetByteArrayRegion(baselinesBytes, 0, len, reinterpret_cast<jbyte*>(&baselines))`.
  6. Call `clCProductivity_ImportBaselines(prod, &baselines, &error)` — this takes `clCError*`, check and `throw_sdk_error` on failure.
  This mirrors the iOS approach: `data.data.withUnsafeBytes { $0.load(as: clCProductivity_Baselines.self) }` — a direct memory reinterpret of the raw byte blob into the C struct. The round-trip is: `on_productivity_baseline_update` serializes struct → `jbyteArray` → Dart receives `Uint8List` → Dart passes `Uint8List` back → `nativeImportProductivityBaselines` receives `jbyteArray` → `GetByteArrayRegion` into struct.
  Implement `nativeResetAccumulatedFatigue(JNIEnv* env, jobject, jlong prodHandle)`: guard handle, call `clCProductivity_ResetAccumulatedFatigue(prod, &error)` — this takes `clCError*`, throw on failure. Add comment: "Metrics values may briefly show stale fatigue during reset."
  Implement `nativeDisposeProductivity(JNIEnv*, jobject, jlong prodHandle)`:
  1. Guard `prodHandle == 0` → early return.
  2. Unregister all five callbacks by passing `nullptr` — all are void-returning without error params.
  3. Lock mutex, `DeleteGlobalRef` all six sinks, set to nullptr, unlock.

- [x] **Task 5: Implement `on_productivity_metrics_update` callback** (depends on Task 4)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Signature: `static void on_productivity_metrics_update(clCProductivity, const clCProductivity_Metrics*) noexcept`.
  Follow the `on_physio_state_changed` callback pattern:
  1. Guard `!g_jvm || !data`.
  2. `AttachCurrentThread` if detached.
  3. Lock mutex, `NewLocalRef` the `g_productivityMetricsSink` and `g_handler`, unlock.
  4. Guard null refs → `goto cleanup`.
  5. Build map with keys matching Dart `ProductivityMetrics.fromMap`: `map_put_long(ts)`, `map_put_float(fatigueScore)`, `map_put_float(reverseFatigueScore)`, `map_put_float(gravityScore)`, `map_put_float(relaxationScore)`, `map_put_float(concentrationScore)`, `map_put_float(productivityScore)`, `map_put_float(currentValue)`, `map_put_float(alpha)`, `map_put_float(productivityBaseline)`, `map_put_float(accumulatedFatigue)`, `map_put_int("fatigueGrowthRate", (jint)data->fatigueGrowthRate)`.
  6. Handle `artifactsData`: if `data->artifactsSize > 0 && data->artifactsData != NULL`, create `jbyteArray artifacts = env->NewByteArray(data->artifactsSize)`, copy with `SetByteArrayRegion`, add via `map_put_object(env, map, "artifactsData", artifacts)`, and `DeleteLocalRef(artifacts)` in cleanup. If no artifacts, omit the key (Dart `fromMap` handles null).
  7. Dispatch via `CallStaticVoidMethod`.
  8. Cleanup: `DeleteLocalRef` map, artifacts (if created), sink_ref, handler_ref; `DetachCurrentThread` if attached.

- [x] **Task 6: Implement `on_productivity_indexes_update` callback** (depends on Task 4)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Signature: `static void on_productivity_indexes_update(clCProductivity, const clCProductivity_Indexes*) noexcept`.
  Standard callback boilerplate (attach, mutex, guard, build map, dispatch, cleanup).
  Map keys matching Dart `ProductivityIndexes.fromMap`: `map_put_long("ts", ...)`, `map_put_int("relaxation", (jint)data->relaxation)`, `map_put_int("stress", (jint)data->stress)`, `map_put_bool("hasArtifacts", (jboolean)data->hasArtifacts)`, `map_put_float("gravityBaseline", ...)`, `map_put_float("productivityBaseline", ...)`, `map_put_float("fatigueBaseline", ...)`, `map_put_float("reverseFatigueBaseline", ...)`, `map_put_float("relaxationBaseline", ...)`, `map_put_float("concentrationBaseline", ...)`.

- [x] **Task 7: Implement remaining callbacks (baseline with dual-dispatch, calibration progress, individual NFB)** (depends on Task 4)
  Files: `android/src/main/cpp/jni_productivity.cpp`
  Three callbacks:

  **`on_productivity_baseline_update(clCProductivity, const clCProductivity_Baselines*)`** — this is the most complex callback because it dispatches to TWO sinks from one SDK callback (matching the iOS pattern in `ProductivityBridge.swift` lines 147–167):
  1. Standard boilerplate: guard `!g_jvm || !data`, `AttachCurrentThread`.
  2. Lock mutex once, `NewLocalRef` THREE refs: `g_productivityBaselinesSink`, `g_productivityCalibratedSink`, and `g_handler`. Unlock.
  3. Check each sink ref independently — either or both may be null.
  4. **Sink 1 — structured map to `baselinesSink`:** If `baselinesSink_ref` is not null, build a map with keys matching Dart `ProductivityBaselines.fromMap`: `ts`, `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration`. Dispatch via `CallStaticVoidMethod(env, dispatcher, g_postSuccess, handler_ref, baselinesSink_ref, baselinesMap)`.
  5. **Sink 2 — raw bytes to `calibratedSink`:** If `calibratedSink_ref` is not null, create a second map via `make_map(env)`. Create `jbyteArray blob = env->NewByteArray(sizeof(clCProductivity_Baselines))`, copy struct bytes via `env->SetByteArrayRegion(blob, 0, sizeof(...), reinterpret_cast<const jbyte*>(data))`, add to map via `map_put_object(env, calibratedMap, "baselines", blob)`. Dispatch via `CallStaticVoidMethod(env, dispatcher, g_postSuccess, handler_ref, calibratedSink_ref, calibratedMap)`.
  6. **Cleanup:** `DeleteLocalRef` for ALL allocated objects — `baselinesMap` (if created), `calibratedMap` (if created), `blob` (if created), `baselinesSink_ref`, `calibratedSink_ref`, `handler_ref`. `DetachCurrentThread` if attached.

  **`on_productivity_calibration_progress(clCProductivity, float)`:** clamp to 0–1 via `fmaxf/fminf` (same as `on_physio_calibration_progress`), map key `"progress"`.

  **`on_productivity_individual_nfb_update(clCProductivity)`:** no-data callback, dispatch an empty `make_map(env)` to `g_productivityIndividualNfbSink` (same pattern as `on_physio_individual_nfb_update`).

  No error callback — `CProductivity.h` does not declare `clCProductivity_SetOnErrorEvent`. Omit entirely.

- [x] **Task 8: Add `jni_productivity.cpp` to CMakeLists.txt**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_productivity.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_cardio.cpp`.

### Phase 2: Kotlin bridge + plugin wiring

- [x] **Task 9: Add `external fun` declarations to `NativeBridge.kt`** (depends on Tasks 1–7)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a `// ── Productivity classifier` section after the Cardio section with:
  - `external fun nativeCreateProductivity(deviceHandle: Long): Long`
  - `external fun nativeCreateProductivityWithIndividualData(deviceHandle: Long, ts: Long, failReason: Int, individualFrequency: Float, individualPeakFrequency: Float, individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float, individualBandwidth: Float, individualNormalizedPower: Float, lowerFrequency: Float, upperFrequency: Float): Long`
  - `external fun nativeSetProductivityMetricsSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetProductivityIndexesSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetProductivityBaselinesSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetProductivityCalibrationProgressSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetProductivityCalibratedSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetProductivityIndividualNfbSink(sink: EventChannel.EventSink?)`
  - `external fun nativeStartProductivityBaselineCalibration(prodHandle: Long)`
  - `external fun nativeImportProductivityBaselines(prodHandle: Long, baselinesBytes: ByteArray)`
  - `external fun nativeResetAccumulatedFatigue(prodHandle: Long)`
  - `external fun nativeDisposeProductivity(prodHandle: Long)`
  No error sink setter — matches the JNI layer which has no error sink.

- [x] **Task 10: Create `ProductivityBridge.kt`** (depends on Task 9)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/ProductivityBridge.kt`
  Follow `PhysioBridge.kt` + `CardioBridge.kt` combined pattern (PhysioBridge has calibration methods, CardioBridge has two factory paths with individual NFB data):
  - `class ProductivityBridge(private val nativeBridge: NativeBridge)`
  - Private `handle: Long = 0L`
  - Inner `ProductivityStreamHandler(setSink: (EventChannel.EventSink?) -> Unit) : EventChannel.StreamHandler` with `onListen`/`onCancel`.
  - Six handler vals: `metricsHandler`, `indexesHandler`, `baselinesHandler`, `calibrationProgressHandler`, `calibratedHandler`, `individualNfbHandler` — each wrapping the corresponding `nativeBridge.nativeSetProductivity*Sink(it)`. No error handler — for consistency with iOS (`ProductivityBridge.swift` returns 6 handlers) and other Android bridges (`PhysioBridge` returns 4, `CardioBridge` returns 3 — none include error handlers). The `productivityError` event channel is handled by `StubStreamHandler` in the plugin.
  - `allStreamHandlers()` returns list of 6 pairs: `"neiry_kit/events/productivityMetrics"`, `"neiry_kit/events/productivityIndexes"`, `"neiry_kit/events/productivityBaselines"`, `"neiry_kit/events/productivityCalibrationProgress"`, `"neiry_kit/events/productivityCalibrated"`, `"neiry_kit/events/productivityIndividualNfb"`.
  - `create(deviceHandle: Long)`: dispose existing, call `nativeBridge.nativeCreateProductivity(deviceHandle)`, wrap `RuntimeException` with `parseSdkError`.
  - `createWithIndividualData(deviceHandle: Long, calibrationData: Map<String, Any>)`: dispose existing, unpack all 10 fields from map (same casting pattern as `CardioBridge.createCalibrated` — `(map["key"] as? Number)?.toFloat() ?: 0f`), call `nativeBridge.nativeCreateProductivityWithIndividualData(...)`, wrap exception. **Note:** no `hasCalibrationData` boolean — data is always present for this factory path.
  - `startBaselineCalibration()`: guard `handle == 0L` throw `FlutterError("NOT_CREATED", ...)`, call `nativeBridge.nativeStartProductivityBaselineCalibration(handle)`.
  - `importBaselines(data: ByteArray)`: guard handle, call `nativeBridge.nativeImportProductivityBaselines(handle, data)`, wrap exception with `parseSdkError`. The `data` parameter is the raw `ByteArray` received from Flutter's standard codec (which delivers Dart's `Uint8List` as `byte[]` on Android). No field unpacking — the bytes are the opaque in-memory representation of `clCProductivity_Baselines`, passed through to JNI which reinterprets them directly into the C struct.
  - `resetAccumulatedFatigue()`: guard handle, wrap `nativeBridge.nativeResetAccumulatedFatigue(handle)` in try/catch, rethrow via `parseSdkError`.
  - `dispose()`: guard `handle != 0L`, call `nativeBridge.nativeDisposeProductivity(handle)`, reset to `0L`.

- [x] **Task 11: Wire `ProductivityBridge` into `NeiryKitPlugin.kt`** (depends on Task 10)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Five changes:
  1. Add `private var productivityBridge: ProductivityBridge? = null` field (alongside the existing bridge fields).
  2. In `onAttachedToEngine`, instantiate `productivityBridge = ProductivityBridge(nativeBridge!!)` after `cardioBridge`.
  3. In the `streamHandlerMap` builder, add productivity handlers: `for ((id, handler) in productivityBridge!!.allStreamHandlers()) { put(id, handler) }` after the cardioBridge loop.
  4. Replace the `handleProductivityCall` stub body with real dispatch:
     - Get `val bridge = productivityBridge ?: return result.error("NOT_INITIALIZED", ...)` and `val devBridge = deviceBridge ?: ...`.
     - `when (call.method)`:
       - `"create"` → `bridge.create(devBridge.requireHandle())`
       - `"createCalibrated"` → extract `calibrationData` from `call.arguments` map (`@Suppress("UNCHECKED_CAST")`, same as `handleNfbCall`), call `bridge.createWithIndividualData(devBridge.requireHandle(), calibrationData!!)`
       - `"startBaselineCalibration"` → `bridge.startBaselineCalibration()`
       - `"importBaselines"` → extract `baselines` from arguments as `ByteArray`: `(call.arguments as? Map<*, *>)?.get("baselines") as? ByteArray`. Flutter's standard codec delivers Dart's `Uint8List` as `byte[]` on Android, so this cast is correct. If null, return `result.error("MISSING_ARGS", "Missing 'baselines'", null)`. Call `bridge.importBaselines(baselines)`.
       - `"resetAccumulatedFatigue"` → `bridge.resetAccumulatedFatigue()`
       - `"dispose"` → `bridge.dispose()`
       - `else` → `result.notImplemented()`
     - All branches: `result.success(null)` after the bridge call. Wrap in `try/catch` for `FlutterError` and `Exception` (same pattern as `handlePhysiologicalCall`).
  5. In `onDetachedFromEngine`, add `productivityBridge?.dispose()` + `productivityBridge = null` before `cardioBridge?.dispose()`.

## Commit Plan
- **Commit 1** (after tasks 1–8): "Add JNI C++ layer for Productivity classifier bridge"
- **Commit 2** (after tasks 9–11): "Wire ProductivityBridge Kotlin class into plugin"
