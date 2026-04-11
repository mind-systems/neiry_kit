# Plan: CardioBridge (Android JNI + Kotlin)

## Context
Implement the Android-side Cardio classifier bridge — JNI C++ layer (`jni_cardio.cpp`) and Kotlin bridge (`CardioBridge.kt`) — mirroring the already-shipped iOS `CardioBridge.swift`. Three EventChannels (cardioState, cardioPpg, cardioCalibratedEvent), two factory paths (plain + calibrated via `clCNFBCalibrator_CreateOrGet`), and plugin registration.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI C++ layer

- [x] **Task 1: Create `jni_cardio.cpp` with extern declarations and file-private state**
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Create the file with standard includes (`<jni.h>`, `<pthread.h>`, `<cstdio>`, `"CCapsuleAPI.h"`). Declare all extern symbols following the pattern from `jni_emotions.cpp` / `jni_physio.cpp`:
  - From `jni_device_locator.cpp`: `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`
  - From `jni_device.cpp`: `make_map`, `map_put_float`, `map_put_long`, `map_put_bool`, `map_put_int`, `map_put_object`
  - From `jni_device_locator.cpp`: `throw_sdk_error`
  DO NOT redefine any of these — `extern` only.
  Declare file-private (`static`) state: three sinks (`g_cardioStateSink`, `g_cardioPpgSink`, `g_cardioCalibratedSink`), one `pthread_mutex_t g_cardio_mutex = PTHREAD_MUTEX_INITIALIZER`.
  Forward-declare three static callback functions: `on_cardio_indexes_update`, `on_cardio_ppg_data`, `on_cardio_calibrated`.

- [x] **Task 2: Implement `nativeCreateCardio` (plain factory)** (depends on Task 1)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Inside `extern "C"` block, implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateCardio(JNIEnv*, jobject, jlong deviceHandle)`:
  1. Cast `deviceHandle` to `clCDevice` via `(clCDevice)(uintptr_t)`.
  2. Call `clCCardio_Create(dev, &error)` — on failure, `throw_sdk_error` and return 0.
  3. Register all three callbacks: `clCCardio_SetOnIndexesUpdateEvent(cardio, on_cardio_indexes_update, &e1)`, `clCCardio_SetOnPPGDataEvent(cardio, on_cardio_ppg_data, &e2)`, `clCCardio_SetOnCalibratedEvent(cardio, on_cardio_calibrated, &e3)`. All three `SetOn*Event` take `clCError*` — check each and `throw_sdk_error` on failure.
  4. Return `(jlong)(uintptr_t)cardio`.

- [x] **Task 3: Implement `nativeCreateCardioCalibrated` (calibrated factory)** (depends on Task 1)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateCardioCalibrated(JNIEnv*, jobject, jlong deviceHandle, jboolean hasCalibrationData, jlong ts, jint failReason, jfloat individualFrequency, jfloat individualPeakFrequency, jfloat individualPeakFrequencyPower, jfloat individualPeakFrequencySuppression, jfloat individualBandwidth, jfloat individualNormalizedPower, jfloat lowerFrequency, jfloat upperFrequency)`:
  1. Cast device handle.
  2. Call `clCNFBCalibrator_CreateOrGet(dev)` — if null, `env->ThrowNew(env->FindClass("java/lang/RuntimeException"), "0|clCNFBCalibrator_CreateOrGet returned null")` and return 0.
  3. If `hasCalibrationData`, populate `clCIndividualNFBData` struct (all 10 fields: `timestampMilli`, `failReason` cast to `clCIndividualNFBCalibrationFailReason`, `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`) and call `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError)` — throw on failure.
  4. Call `clCCardio_CreateCalibrated(dev, calibrator, &error)` — throw on failure.
  5. Register all three callbacks (same as Task 2).
  6. Return handle as `jlong`.
  Follow the exact pattern from `nativeCreateNfbCalibrated` in `jni_nfb.cpp` (lines 56–112).

- [x] **Task 4: Implement sink setters and dispose** (depends on Task 1)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Implement three sink-setter JNI functions following the `jni_nfb.cpp` pattern (lock mutex, `DeleteGlobalRef` old sink, `NewGlobalRef` new sink):
  - `nativeSetCardioStateSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetCardioPpgSink(JNIEnv*, jobject, jobject sink)`
  - `nativeSetCardioCalibratedSink(JNIEnv*, jobject, jobject sink)`
  Implement `nativeDisposeCardio(JNIEnv*, jobject, jlong cardioHandle)`:
  1. Guard `cardioHandle == 0` → early return.
  2. Unregister all three callbacks by passing `nullptr`: `clCCardio_SetOnIndexesUpdateEvent(cardio, nullptr, &e)`, same for PPG and Calibrated. No `clCCardio_Destroy` — SDK manages lifecycle.
  3. Lock mutex, `DeleteGlobalRef` all three sinks, set to nullptr, unlock.

- [x] **Task 5: Implement `on_cardio_indexes_update` callback** (depends on Task 4)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Signature: `static void on_cardio_indexes_update(clCCardio, const clCCardio_Data* data) noexcept`.
  Follow the `on_nfb_state_changed` callback pattern exactly:
  1. Guard `!g_jvm || !data`.
  2. `AttachCurrentThread` if detached.
  3. Lock mutex, `NewLocalRef` the `g_cardioStateSink` and `g_handler`, unlock.
  4. Guard null refs → `goto cleanup`.
  5. Build map with: `map_put_long(ts)`, `map_put_float(heartRate)`, `map_put_float(stressIndex)`, `map_put_float(kaplanIndex)`, `map_put_bool(hasArtifacts, (jboolean)(data->hasArtifacts != 0))`, `map_put_bool(skinContact, (jboolean)(data->skinContact != 0))`, `map_put_bool(motionArtifacts, (jboolean)(data->motionArtifacts != 0))`, `map_put_bool(metricsAvailable, (jboolean)(data->metricsAvailable != 0))`.
  6. Dispatch via `env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map)`.
  7. `cleanup:` label — `DeleteLocalRef` map, sink_ref, handler_ref; `DetachCurrentThread` if attached.
  Bool fields: cast `(jboolean)(data->field != 0)` as specified — the SDK header initializes bools to `0.F` (float literal, header bug), reading as bool is fine but the `!= 0` cast ensures correctness.

- [x] **Task 6: Implement `on_cardio_ppg_data` callback** (depends on Task 4)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Signature: `static void on_cardio_ppg_data(clCCardio, clCPPGTimedData ppgData) noexcept`.
  PPG uses accessor functions (not direct struct fields):
  1. Standard JVM attach + mutex lock for `g_cardioPpgSink`.
  2. Call `int32_t count = clCPPGTimedData_GetCount(ppgData)`.
  3. Create `jfloatArray values = env->NewFloatArray(count)` and `jlongArray timestamps = env->NewLongArray(count)`.
  4. Loop `0..count`: populate temp buffers with `clCPPGTimedData_GetValue(ppgData, i)` and `(jlong)clCPPGTimedData_GetTimestampMilli(ppgData, i)`.
  5. `SetFloatArrayRegion` / `SetLongArrayRegion` to copy buffers.
  6. Build map: `map_put_int("sampleCount", count)`, `map_put_object("values", values)`, `map_put_object("timestamps", timestamps)`.
  7. Dispatch and cleanup (delete local refs for values, timestamps, map, sink_ref, handler_ref; detach).
  Follow the resistance callback pattern in `jni_device.cpp` (lines 1092–1144) for array creation.

- [x] **Task 7: Implement `on_cardio_calibrated` callback** (depends on Task 4)
  Files: `android/src/main/cpp/jni_cardio.cpp`
  Signature: `static void on_cardio_calibrated(clCCardio) noexcept`.
  1. Standard JVM attach + mutex lock for `g_cardioCalibratedSink`.
  2. Create an empty map via `make_map(env)` — no fields (matching iOS `[:]`).
  3. Dispatch and cleanup.

- [x] **Task 8: Add `jni_cardio.cpp` to CMakeLists.txt**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_cardio.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_physio.cpp`.

### Phase 2: Kotlin bridge + plugin wiring

- [x] **Task 9: Create `CardioBridge.kt`** (depends on Tasks 1–7)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/CardioBridge.kt`
  Follow the `NfbBridge.kt` pattern (which has both plain + calibrated factory):
  - `class CardioBridge(private val nativeBridge: NativeBridge)`
  - Private `handle: Long = 0L`
  - Inner `CardioStreamHandler(setSink: (EventChannel.EventSink?) -> Unit) : EventChannel.StreamHandler` with `onListen`/`onCancel` delegating to `setSink`.
  - Three handler vals: `cardioStateHandler`, `cardioPpgHandler`, `cardioCalibratedHandler` — each wrapping the corresponding `nativeBridge.nativeSetCardio*Sink(it)`.
  - `allStreamHandlers()` returns list of 3 pairs: `"neiry_kit/events/cardioData"`, `"neiry_kit/events/ppgData"`, `"neiry_kit/events/cardioCalibratedEvent"`.
  - `create(deviceHandle: Long)`: dispose existing, call `nativeBridge.nativeCreateCardio(deviceHandle)`, wrap `RuntimeException` with `parseSdkError`.
  - `createCalibrated(deviceHandle: Long, calibrationData: Map<String, Any>?)`: dispose existing, unpack 10 fields from map (same pattern as `NfbBridge.createCalibrated` — `?.toLong()` / `?.toFloat()` with `?: 0` defaults), call `nativeBridge.nativeCreateCardioCalibrated(...)`, wrap exception.
  - `dispose()`: guard `handle != 0L`, call `nativeBridge.nativeDisposeCardio(handle)`, reset to `0L`.

- [x] **Task 10: Add `external fun` declarations to `NativeBridge.kt`** (depends on Tasks 1–7)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a `// ── Cardio classifier` section after the PhysiologicalStates section with:
  - `external fun nativeCreateCardio(deviceHandle: Long): Long`
  - `external fun nativeCreateCardioCalibrated(deviceHandle: Long, hasCalibrationData: Boolean, ts: Long, failReason: Int, individualFrequency: Float, individualPeakFrequency: Float, individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float, individualBandwidth: Float, individualNormalizedPower: Float, lowerFrequency: Float, upperFrequency: Float): Long`
  - `external fun nativeSetCardioStateSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetCardioPpgSink(sink: EventChannel.EventSink?)`
  - `external fun nativeSetCardioCalibratedSink(sink: EventChannel.EventSink?)`
  - `external fun nativeDisposeCardio(cardioHandle: Long)`

- [x] **Task 11: Wire `CardioBridge` into `NeiryKitPlugin.kt`** (depends on Tasks 9–10)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Four changes:
  1. Add `private var cardioBridge: CardioBridge? = null` field.
  2. In `onAttachedToEngine`, instantiate `cardioBridge = CardioBridge(nativeBridge!!)` after `physioBridge`.
  3. In the `streamHandlerMap` builder, add cardio handlers: `for ((id, handler) in cardioBridge!!.allStreamHandlers()) { put(id, handler) }`.
  4. Replace the stub `handleCardioCall` body with real dispatch:
     - Get `val bridge = cardioBridge ?: return result.error("NOT_INITIALIZED", ...)` and `val devBridge = deviceBridge ?: ...`.
     - `when (call.method)`:
       - `"create"` → `bridge.create(devBridge.requireHandle())`
       - `"createCalibrated"` → extract `calibrationData` from `call.arguments` map (same as `handleNfbCall`), call `bridge.createCalibrated(devBridge.requireHandle(), calibrationData)`
       - `"dispose"` → `bridge.dispose()`
       - `else` → `result.notImplemented()`
     - Wrap in `try/catch` for `FlutterError` and `Exception` (same as other handlers).
  5. In `onDetachedFromEngine`, add `cardioBridge?.dispose()` + `cardioBridge = null` before `physioBridge?.dispose()` (classifier bridges dispose before device/locator bridges).

## Commit Plan
- **Commit 1** (after tasks 1–8): "Add JNI C++ layer for Cardio classifier bridge"
- **Commit 2** (after tasks 9–11): "Wire CardioBridge Kotlin class into plugin"
