# Plan: PhysioBridge — Android JNI + Kotlin bridge for PhysiologicalStates classifier

## Context
Implement the Android-side bridge for the `clCPhysiologicalStates` classifier, mirroring the existing iOS `PhysioBridge.swift`. This adds `jni_physio.cpp` (C++ JNI layer) and `PhysioBridge.kt` (Kotlin bridge), wires them into `NeiryKitPlugin.kt` and the CMake build, and adds the required `external fun` declarations to `NativeBridge.kt`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI C++ layer

- [x] **Task 1: Create `jni_physio.cpp` — globals, forward declarations, and JNI create/dispose functions**
  Files: `android/src/main/cpp/jni_physio.cpp`
  Create a new file following the exact structure of `jni_emotions.cpp`. At the top, declare extern references to shared globals from `jni_device_locator.cpp` (`g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`) and map helpers from `jni_device.cpp` (`make_map`, `map_put_float`, `map_put_long`, `map_put_bool`). Also extern `throw_sdk_error` from `jni_device_locator.cpp`. Declare four file-private static globals for EventSink refs (`g_physioStateSink`, `g_physioCalibrationProgressSink`, `g_physioCalibratedSink`, `g_physioIndividualNfbSink`) and a single `pthread_mutex_t g_physio_mutex = PTHREAD_MUTEX_INITIALIZER`. Add forward declarations for four static callback functions: `on_physio_state_changed`, `on_physio_calibration_progress`, `on_physio_calibrated`, `on_physio_individual_nfb_update`. Implement `nativeCreatePhysio(JNIEnv*, jobject, jlong deviceHandle)`: cast handle to `clCDevice`, call `clCPhysiologicalStates_Create(dev, &error)`, check `error.success` and `throw_sdk_error` on failure, then register all four callbacks via `clCPhysiologicalStates_SetOn*Event` — each taking `clCError*` — check error after each and `throw_sdk_error` on failure, return handle as `jlong`. Implement `nativeDisposePhysio(JNIEnv*, jobject, jlong physioHandle)`: early-return if 0, cast handle, unregister all four callbacks by passing `nullptr` (each takes `clCError*`, but ignore errors on teardown), then lock mutex, `DeleteGlobalRef` all four sinks if non-null and set to nullptr, unlock.

- [x] **Task 2: Implement four sink setter JNI functions in `jni_physio.cpp`**
  Files: `android/src/main/cpp/jni_physio.cpp`
  Add four JNI functions following the exact pattern of `nativeSetEmotionsStateSink`/`nativeSetEmotionsErrorSink` in `jni_emotions.cpp`: `nativeSetPhysioStateSink`, `nativeSetPhysioCalibrationProgressSink`, `nativeSetPhysioCalibratedSink`, `nativeSetPhysioIndividualNfbSink`. Each locks `g_physio_mutex`, deletes old global ref if non-null, creates new global ref if sink is non-null, unlocks. All four share the single `g_physio_mutex`.

- [x] **Task 3: Implement `nativeStartBaselineCalibration` and `nativeImportBaselines` JNI functions** (depends on Task 1)
  Files: `android/src/main/cpp/jni_physio.cpp`
  Add `nativeStartBaselineCalibration(JNIEnv*, jobject, jlong physioHandle)`: cast handle, call `clCPhysiologicalStates_StartBaselineCalibration(physio)` — no error param, no error check. Add `nativeImportBaselines(JNIEnv*, jobject, jlong physioHandle, jlong ts, jfloat alpha, jfloat beta, jfloat alphaGravity, jfloat betaGravity, jfloat concentration)`: cast handle, construct `clCPhysiologicalStates_Baselines` struct from the 6 parameters (set `timestampMilli = (int64_t)ts`, `alpha = alpha`, etc.), call `clCPhysiologicalStates_ImportBaselines(physio, &baselines)` — no error param. This matches iOS `PhysioBridge.swift:importBaselines(map:)` where baselines are deserialized from a map of 6 fields with keys `ts/alpha/beta/alphaGravity/betaGravity/concentration`.

- [x] **Task 4: Implement the four C callbacks in `jni_physio.cpp`** (depends on Tasks 1, 2)
  Files: `android/src/main/cpp/jni_physio.cpp`
  Implement all four callbacks following the exact pattern of `on_emotions_state_changed` in `jni_emotions.cpp` — `GetEnv`/`AttachCurrentThread`, `NewLocalRef` under mutex lock, `goto cleanup` with `DeleteLocalRef` + `DetachCurrentThread`.

  **`on_physio_state_changed(clCPhysiologicalStates, const clCPhysiologicalStates_Value*)`**: guard `!g_jvm || !data`, build map with 9 fields: `map_put_long(ts)`, `map_put_float` for `relaxation/fatigue/none/concentration/involvement/stress`, `map_put_bool` for `nfbArtifacts` (cast `(jboolean)data->nfbArtifacts`), `map_put_bool` for `cardioArtifacts`. Post via `g_postSuccess` with `g_physioStateSink` local ref.

  **`on_physio_calibration_progress(clCPhysiologicalStates, float progress)`**: guard `!g_jvm`, clamp progress to `[0.0, 1.0]` (`fmaxf(0.0f, fminf(1.0f, progress))`), build map with single field `map_put_float("progress", clamped)`. Post via `g_physioCalibrationProgressSink`.

  **`on_physio_calibrated(clCPhysiologicalStates, const clCPhysiologicalStates_Baselines*)`**: guard `!g_jvm || !baselines`, build map with 6 fields: `map_put_long("ts", baselines->timestampMilli)`, `map_put_float` for `alpha/beta/alphaGravity/betaGravity/concentration`. Post via `g_physioCalibratedSink`. Keys must match iOS exactly: `ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`.

  **`on_physio_individual_nfb_update(clCPhysiologicalStates)`**: guard `!g_jvm`, build empty map via `make_map(env)` — no fields added. Post via `g_physioIndividualNfbSink`. This matches iOS `bridge.individualNfbHandler.send([:])`.

### Phase 2: Kotlin bridge + NativeBridge declarations

- [x] **Task 5: Add PhysioBridge `external fun` declarations to `NativeBridge.kt`** (depends on Tasks 1-4)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a `// ── PhysiologicalStates classifier ──` section after the Emotions section with these declarations:
  - `external fun nativeCreatePhysio(deviceHandle: Long): Long`
  - `external fun nativeSetPhysioStateSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetPhysioCalibrationProgressSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetPhysioCalibratedSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetPhysioIndividualNfbSink(sink: EventChannel.EventSink?)`
  - `external fun nativeStartBaselineCalibration(physioHandle: Long)`
  - `external fun nativeImportBaselines(physioHandle: Long, ts: Long, alpha: Float, beta: Float, alphaGravity: Float, betaGravity: Float, concentration: Float)`
  - `external fun nativeDisposePhysio(physioHandle: Long)`

- [x] **Task 6: Create `PhysioBridge.kt`** (depends on Task 5)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/PhysioBridge.kt`
  Create following the exact structure of `EmotionsBridge.kt`. Constructor takes `NativeBridge`. Private `var handle: Long = 0L`. Inner class `PhysioStreamHandler` with `setSink` lambda (same as `EmotionsStreamHandler`). Four handler instances:
  - `physioStateHandler` → `nativeBridge.nativeSetPhysioStateSink(it)`
  - `calibrationProgressHandler` → `nativeBridge.nativeSetPhysioCalibrationProgressSink(it)`
  - `calibratedHandler` → `nativeBridge.nativeSetPhysioCalibratedSink(it)`
  - `individualNfbHandler` → `nativeBridge.nativeSetPhysioIndividualNfbSink(it)`

  `allStreamHandlers()` returns 4 pairs:
  - `"neiry_kit/events/physiologicalState"` → `physioStateHandler`
  - `"neiry_kit/events/physiologicalCalibrationProgress"` → `calibrationProgressHandler`
  - `"neiry_kit/events/physiologicalCalibrated"` → `calibratedHandler`
  - `"neiry_kit/events/physiologicalIndividualNfb"` → `individualNfbHandler`

  Methods:
  - `create(deviceHandle: Long)` — if `handle != 0L` call `dispose()` first, then `nativeBridge.nativeCreatePhysio(deviceHandle)` wrapped in try/catch `RuntimeException` → `parseSdkError(...)`.
  - `startBaselineCalibration()` — guard `handle != 0L` or throw `FlutterError("NOT_CREATED", "PhysioBridge not created — call create first", null)`, call `nativeBridge.nativeStartBaselineCalibration(handle)`.
  - `importBaselines(map: Map<String, Any>)` — guard handle, extract 6 fields from map (`ts` as Long via `(map["ts"] as Number).toLong()`, `alpha/beta/alphaGravity/betaGravity/concentration` as Float via `(map[key] as Number).toFloat()`), call `nativeBridge.nativeImportBaselines(handle, ts, alpha, beta, alphaGravity, betaGravity, concentration)`.
  - `dispose()` — if `handle != 0L`, call `nativeBridge.nativeDisposePhysio(handle)`, set `handle = 0L`.

### Phase 3: Plugin wiring + build

- [x] **Task 7: Wire `PhysioBridge` into `NeiryKitPlugin.kt`** (depends on Task 6)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Add `private var physioBridge: PhysioBridge? = null` field alongside the other bridges. In `onAttachedToEngine`: instantiate `physioBridge = PhysioBridge(nativeBridge!!)` after `emotionsBridge`. In the `streamHandlerMap` builder, add a loop for `physioBridge!!.allStreamHandlers()` after the emotions block. Replace the stub `handlePhysiologicalCall` with a real implementation following the exact pattern of `handleEmotionsCall`:
  - Get `bridge` and `devBridge` with null-safe guards returning `result.error("NOT_INITIALIZED", ...)`
  - Dispatch `call.method`:
    - `"create"` → `bridge.create(devBridge.requireHandle())`, `result.success(null)`
    - `"startBaselineCalibration"` → `bridge.startBaselineCalibration()`, `result.success(null)`
    - `"importBaselines"` → extract `@Suppress("UNCHECKED_CAST") val baselines = (call.arguments as? Map<*, *>)?.get("baselines") as? Map<String, Any> ?: return result.error("INVALID_ARGS", "Missing 'baselines'", null)`, call `bridge.importBaselines(baselines)`, `result.success(null)`
    - `"dispose"` → `bridge.dispose()`, `result.success(null)`
    - `else` → `result.notImplemented()`
  - Catch `FlutterError` and general `Exception` as in other handlers.

  In `onDetachedFromEngine`: add `physioBridge?.dispose()` + `physioBridge = null` before the existing `emotionsBridge?.dispose()` line (teardown order: classifiers before device bridges — physio before emotions to maintain alphabetical consistency is fine, but must be before device/locator cleanup).

- [x] **Task 8: Add `jni_physio.cpp` to CMake build**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_physio.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_emotions.cpp`.

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add jni_physio.cpp with PhysiologicalStates JNI callbacks and lifecycle functions"
- **Commit 2** (after tasks 5-8): "Wire PhysioBridge into Kotlin layer, plugin dispatch, and CMake build"
