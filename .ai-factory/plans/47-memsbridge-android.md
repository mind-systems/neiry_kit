# Plan: MEMSBridge Android

## Context
Implement the Android-side MEMS classifier bridge — a JNI C++ file (`jni_mems.cpp`) and a Kotlin bridge (`MemsBridge.kt`) — mirroring the iOS `MemsBridge.swift` that already ships create / createCalibrated / dispose plus a timed-data EventChannel. The Dart API (`MEMSClassifier`) and model (`MemsSample`) already exist; this milestone only adds the native Android half.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI native layer

- [x] **Task 1: Create `jni_mems.cpp`**
  Files: `android/src/main/cpp/jni_mems.cpp`
  Create the JNI C++ bridge following the exact pattern established by `jni_cardio.cpp` (closest analog — timed data with count/accessor iteration).

  **Extern declarations** (from `jni_device.cpp` and `jni_device_locator.cpp` — do NOT redefine):
  ```cpp
  extern JavaVM*   g_jvm;
  extern jobject   g_handler;
  extern jclass    g_dispatcher_class;
  extern jmethodID g_postSuccess;
  extern jobject   make_map(JNIEnv*);
  extern void      map_put_float(JNIEnv*, jobject, const char*, jfloat);
  extern void      map_put_long(JNIEnv*, jobject, const char*, jlong);
  extern void      map_put_object(JNIEnv*, jobject, const char*, jobject);
  extern void      map_put_int(JNIEnv*, jobject, const char*, jint);
  extern void      throw_sdk_error(JNIEnv*, const clCError*);
  ```

  **File-private state:**
  ```cpp
  static jobject         g_memsDataSink = nullptr;
  static pthread_mutex_t g_mems_mutex   = PTHREAD_MUTEX_INITIALIZER;
  ```

  **Forward declaration:**
  ```cpp
  static void on_mems_data(clCMEMS, clCMEMSTimedData memsData) noexcept;
  ```
  Note: `clCMEMSTimedData` is already a typedef pointer (opaque handle) — do NOT add `*`. All callbacks must be `noexcept` per codebase convention (see `jni_cardio.cpp:35-37`).

  **Exported JNI functions** (all on `NativeBridge`):

  1. `nativeCreateMems(jlong deviceHandle)` → `jlong`
     - Cast device handle with intermediate `uintptr_t`: `clCDevice dev = (clCDevice)(uintptr_t)deviceHandle` (suppresses sign-extension warning on jlong→pointer, per pattern at `jni_cardio.cpp:47`).
     - Call `clCMEMS_Create(dev, &error)`. On error: `throw_sdk_error`, return 0.
     - Register callback via `clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, on_mems_data, &error)`. On error: `throw_sdk_error`, return 0.
     - Return `(jlong)(uintptr_t)mems`.

  2. `nativeCreateMemsCalibrated(jlong deviceHandle, jboolean hasCalibrationData, jlong ts, jint failReason, jfloat individualFrequency, jfloat individualPeakFrequency, jfloat individualPeakFrequencyPower, jfloat individualPeakFrequencySuppression, jfloat individualBandwidth, jfloat individualNormalizedPower, jfloat lowerFrequency, jfloat upperFrequency)` → `jlong`
     - Cast: `clCDevice dev = (clCDevice)(uintptr_t)deviceHandle`.
     - Call `clCNFBCalibrator_CreateOrGet(dev)`. **Null-check** — if null, throw `RuntimeException` with `"0|clCNFBCalibrator_CreateOrGet returned null"` and return 0.
     - If `hasCalibrationData`: populate a `clCIndividualNFBData` struct from the parameters (same field mapping as `jni_cardio.cpp:96-106`) and call `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError)`. Check `importError.success` — on failure: `throw_sdk_error(env, &importError)`, return 0. (The function name is `clCNFBCalibrator_ImportIndividualNFBData`, not `clCNFBCalibrator_Import`, and takes a third `clCError*` parameter — see `jni_cardio.cpp:108-113`.)
     - Call `clCMEMS_CreateCalibrated(dev, calibrator, &error)`. On error: `throw_sdk_error`, return 0.
     - Register callback same as `nativeCreateMems`.
     - Return `(jlong)(uintptr_t)mems`.

  3. `nativeSetMemsDataSink(jobject sink)` → `void`
     - Lock `g_mems_mutex`.
     - If `g_memsDataSink` is non-null, `DeleteGlobalRef`, set to `nullptr`.
     - If `sink` is non-null, `NewGlobalRef(sink)`, else store `nullptr`.
     - Unlock.

  4. `nativeDisposeMems(jlong memsHandle)` → `void`
     - **Null guard first:** `if (memsHandle == 0) return;` (per `jni_cardio.cpp:187`).
     - Cast: `clCMEMS mems = (clCMEMS)(uintptr_t)memsHandle`.
     - Clear callback: `clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, nullptr, &error)`.
     - Lock `g_mems_mutex`. **Null-check** `g_memsDataSink` before calling `DeleteGlobalRef` (calling `DeleteGlobalRef(nullptr)` causes a JNI abort — follow the pattern at `jni_cardio.cpp:196-199`):
       ```cpp
       if (g_memsDataSink) {
           env->DeleteGlobalRef(g_memsDataSink);
           g_memsDataSink = nullptr;
       }
       ```
     - Unlock.

  **Callback** `on_mems_data(clCMEMS, clCMEMSTimedData memsData) noexcept` (file-static, not `extern "C"`):
  - Guard: `if (!g_jvm || !memsData) return;`
  - Attach thread if detached (`GetEnv` / `AttachCurrentThread`), track `attached` bool.
  - Lock `g_mems_mutex`, take `NewLocalRef` of `g_memsDataSink` → `sink_ref` and `g_handler` → `handler_ref`, unlock.
  - If either is null → `goto cleanup`.
  - Read `count = clCMEMSTimedData_GetCount(memsData)`.
  - Build a Java `ArrayList` of maps using the JNI pattern from `jni_device_locator.cpp:33-36`:
    ```cpp
    jclass    alClass = env->FindClass("java/util/ArrayList");
    jmethodID alCtor  = env->GetMethodID(alClass, "<init>", "()V");
    jmethodID alAdd   = env->GetMethodID(alClass, "add", "(Ljava/lang/Object;)Z");
    jobject   list    = env->NewObject(alClass, alCtor);
    env->DeleteLocalRef(alClass);
    ```
  - For each sample `i` in `0..<count`:
    - `clCPoint3d acc = clCMEMSTimedData_GetAccelerometer(memsData, i)` — no `clCError*`.
    - `clCPoint3d gyro = clCMEMSTimedData_GetGyroscope(memsData, i)` — no `clCError*`.
    - `jlong ts = clCMEMSTimedData_GetTimestampMilli(memsData, i)` — no `clCError*`.
    - `jobject sample = make_map(env)`.
    - `map_put_float(env, sample, "ax", acc.x)`, `"ay"`, `"az"`, `"gx"`, `"gy"`, `"gz"` from `gyro`, `map_put_long(env, sample, "ts", ts)`.
    - `env->CallBooleanMethod(list, alAdd, sample)`.
    - **Immediately** `env->DeleteLocalRef(sample)` after adding to the list — do NOT defer to `cleanup:`. This prevents JNI local ref table overflow for large batches (same pattern as `jni_device_locator.cpp:75-77`).
  - Dispatch: `CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, list)`.
  - `cleanup:` — `DeleteLocalRef` for `list`, `sink_ref`, `handler_ref`. `DetachCurrentThread` if `attached`.

- [x] **Task 2: Add `jni_mems.cpp` to CMakeLists.txt**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_mems.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_productivity.cpp` (alphabetical or by domain — follow existing order).

### Phase 2: Kotlin bridge and plugin wiring

- [x] **Task 3: Add MEMS native function declarations to `NativeBridge.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a `// ── MEMS sensor ──` section (following the existing comment-header convention) with:
  ```kotlin
  external fun nativeCreateMems(deviceHandle: Long): Long
  external fun nativeCreateMemsCalibrated(
      deviceHandle: Long,
      hasCalibrationData: Boolean,
      ts: Long, failReason: Int,
      individualFrequency: Float, individualPeakFrequency: Float,
      individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float,
      individualBandwidth: Float, individualNormalizedPower: Float,
      lowerFrequency: Float, upperFrequency: Float
  ): Long
  external fun nativeSetMemsDataSink(sink: EventChannel.EventSink?)
  external fun nativeDisposeMems(memsHandle: Long)
  ```

- [x] **Task 4: Create `MemsBridge.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/MemsBridge.kt`
  Follow the `CardioBridge.kt` pattern exactly:

  - `class MemsBridge(private val nativeBridge: NativeBridge)` with `private var handle: Long = 0L`.
  - Inner `MemsStreamHandler(setSink: (EventChannel.EventSink?) -> Unit) : EventChannel.StreamHandler` — `onListen` calls `setSink(events)`, `onCancel` calls `setSink(null)`.
  - Single handler instance: `val memsDataHandler = MemsStreamHandler { nativeBridge.nativeSetMemsDataSink(it) }`.
  - `fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>>` returning `listOf("neiry_kit/events/memsData" to memsDataHandler)`.
  - `fun create(deviceHandle: Long)` — calls `nativeBridge.nativeCreateMems(deviceHandle)`, stores result in `handle`. Wrap in try/catch, parse `RuntimeException` via `parseSdkError`.
  - `fun createCalibrated(deviceHandle: Long, calibrationData: Map<String, Any>?)` — unpack the 10 calibration fields from the map (same keys as `CardioBridge`: `ts`, `failReason`, `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`), defaulting absent values to 0. Set `hasCalibrationData = calibrationData != null`. Call `nativeBridge.nativeCreateMemsCalibrated(...)`, store handle. Wrap in try/catch with `parseSdkError`.
  - `fun dispose()` — if `handle != 0L`, call `nativeBridge.nativeDisposeMems(handle)`, reset to 0.

- [x] **Task 5: Register MEMS channels and bridge in `NeiryKitPlugin.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`

  1. Add field: `private var memsBridge: MemsBridge? = null`.
  2. In `onAttachedToEngine`: instantiate `memsBridge = MemsBridge(nativeBridge!!)` (after existing bridge instantiations).
  3. Add `"neiry_kit/mems"` to the `methodChannelIds` list (MethodChannel for create/createCalibrated/dispose).
  4. In the `streamHandlerMap` build block: add `for ((id, handler) in memsBridge!!.allStreamHandlers()) { put(id, handler) }` so `neiry_kit/events/memsData` gets a real handler instead of `StubStreamHandler`.
  5. In `handleMethodCall` dispatch (`when` block): add `"neiry_kit/mems" -> handleMemsCall(call, result)`.
  6. Add private method `handleMemsCall(call: MethodCall, result: Result)`:
     - Guard: `val bridge = memsBridge ?: return result.error(...)`.
     - Guard: `val devBridge = deviceBridge ?: return result.error(...)`.
     - `when (call.method)`:
       - `"create"` — call `bridge.create(devBridge.requireHandle())`, `result.success(null)`. Do NOT extract `serial` from args — no other classifier handler does this; the serial is only used by the Dart `EventChannel.receiveBroadcastStream()` call, not by the MethodChannel (see `handleCardioCall` at lines 391-393).
       - `"createCalibrated"` — extract `calibrationData` map from args via `(call.arguments as? Map<*, *>)?.get("calibrationData") as? Map<String, Any>`, call `bridge.createCalibrated(devBridge.requireHandle(), calibrationData)`, `result.success(null)`.
       - `"dispose"` — call `bridge.dispose()`, `result.success(null)`.
       - `else -> result.notImplemented()`.
     - Wrap in try/catch for `FlutterError` and generic `Exception`, same as `handleCardioCall`.
  7. In `onDetachedFromEngine`: add `memsBridge?.dispose(); memsBridge = null` (before existing bridge disposals or following the reverse-order convention).

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add JNI MEMS bridge and register in CMake build"
- **Commit 2** (after tasks 3-5): "Wire MemsBridge Kotlin class and register channels in plugin"
