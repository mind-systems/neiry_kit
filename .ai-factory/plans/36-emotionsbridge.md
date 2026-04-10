# Plan: EmotionsBridge (Android)

## Context
Implement the Android JNI + Kotlin bridge for the `clCEmotions` classifier — two EventChannels (state updates + errors), no calibration, no Destroy. Mirrors the existing iOS `EmotionsBridge.swift` and follows the exact JNI pattern established by `jni_nfb.cpp` + `NfbBridge.kt`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI layer

- [x] **Task 1: Create `jni_emotions.cpp`**
  Files: `android/src/main/cpp/jni_emotions.cpp`
  Create the C++ JNI file following the `jni_nfb.cpp` pattern exactly. Structure:

  **Extern declarations** — declare (do NOT redefine) shared globals and helpers:
  - From `jni_device_locator.cpp`: `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`, `throw_sdk_error`
  - From `jni_device.cpp`: `make_map`, `map_put_float`, `map_put_long`, `map_put_string`

  **File-private state:**
  - `static jobject g_emotionsStateSink = nullptr`
  - `static jobject g_emotionsErrorSink = nullptr`
  - `static pthread_mutex_t g_emotions_mutex = PTHREAD_MUTEX_INITIALIZER`

  **Callback forward declarations:**
  - `static void on_emotions_state_changed(clCEmotions, const clCEmotions_States*) noexcept`
  - `static void on_emotions_error(clCEmotions, const char*) noexcept`

  **JNI functions** (all inside `extern "C"`, JNI symbol prefix `Java_com_neiry_neiry_1kit_NativeBridge_`):

  1. `nativeCreateEmotions(JNIEnv*, jobject, jlong deviceHandle) → jlong` — cast `deviceHandle` to `clCDevice`, call `clCEmotions_Create(dev, &error)`, check `error.success` and `throw_sdk_error` on failure, then register both callbacks via `clCEmotions_SetOnEmotionalStatesUpdateEvent` and `clCEmotions_SetOnErrorEvent`. **These two SetOn*Event calls take NO `clCError*`** — call directly, no error check. Return handle as `(jlong)(uintptr_t)`.

  2. `nativeSetEmotionsStateSink(JNIEnv*, jobject, jobject sink)` — mutex-guarded global ref swap: lock → `DeleteGlobalRef` old if non-null → `NewGlobalRef` new if non-null → unlock. Identical to `nativeSetNfbStateSink`.

  3. `nativeSetEmotionsErrorSink(JNIEnv*, jobject, jobject sink)` — same pattern for error sink.

  4. `nativeDisposeEmotions(JNIEnv*, jobject, jlong emotionsHandle)` — early-return if handle is 0. Cast to `clCEmotions`, unregister both callbacks by passing `nullptr`, then under mutex `DeleteGlobalRef` both sinks and null them. Mirrors `nativeDisposeNfb`.

  **Callbacks:**

  `on_emotions_state_changed` — guard `g_jvm` and `data`, attach thread if needed, snapshot `g_emotionsStateSink` and `g_handler` as `NewLocalRef` under lock, build map with keys: `ts` (jlong, `data->timestampMilli`), `attention` (jfloat), `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl` — matches iOS map shape exactly. Dispatch via `CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map)`. Cleanup: `DeleteLocalRef` map/sink_ref/handler_ref, `DetachCurrentThread` if attached. Use `goto cleanup` pattern.

  `on_emotions_error` — guard `g_jvm`, attach, snapshot `g_emotionsErrorSink` + `g_handler` under lock, build map with key `message` (string, null-coalesce to `""`). Same dispatch and cleanup pattern.

- [x] **Task 2: Add `jni_emotions.cpp` to CMake build**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_emotions.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_nfb_calibrator.cpp`.

### Phase 2: Kotlin layer

- [x] **Task 3: Add `external fun` declarations to `NativeBridge.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a new `// ── Emotions classifier ──` section after the NFB calibrator section with four declarations:
  ```kotlin
  external fun nativeCreateEmotions(deviceHandle: Long): Long
  external fun nativeSetEmotionsStateSink(sink: EventChannel.EventSink?)
  external fun nativeSetEmotionsErrorSink(sink: EventChannel.EventSink?)
  external fun nativeDisposeEmotions(emotionsHandle: Long)
  ```

- [x] **Task 4: Create `EmotionsBridge.kt`** (depends on Task 3)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/EmotionsBridge.kt`
  Create Kotlin bridge class following the `NfbBridge.kt` pattern:

  - Constructor takes `NativeBridge`.
  - Private `handle: Long = 0L`.
  - Inner `EmotionsStreamHandler` class identical to `NfbStreamHandler` — takes `(EventChannel.EventSink?) -> Unit` lambda, delegates `onListen`/`onCancel`.
  - Two handler instances:
    - `emotionsStateHandler` → `nativeBridge.nativeSetEmotionsStateSink(it)`
    - `emotionsErrorHandler` → `nativeBridge.nativeSetEmotionsErrorSink(it)`
  - `allStreamHandlers()` returns list of pairs: `"neiry_kit/events/emotionsState"` and `"neiry_kit/events/emotionsError"`.
  - `create(deviceHandle: Long)` — if handle non-zero, call `dispose()` first; wrap `nativeBridge.nativeCreateEmotions(deviceHandle)` in try/catch, parse with `parseSdkError()` on `RuntimeException`. **No calibrated factory path** — Emotions has only one Create.
  - `dispose()` — if handle non-zero, call `nativeBridge.nativeDisposeEmotions(handle)`, reset to 0.

### Phase 3: Plugin wiring

- [x] **Task 5: Wire `EmotionsBridge` into `NeiryKitPlugin.kt`** (depends on Task 4)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Four integration points:

  1. **Field declaration** — add `private var emotionsBridge: EmotionsBridge? = null` alongside the other bridge fields.

  2. **`onAttachedToEngine`** — instantiate `emotionsBridge = EmotionsBridge(nativeBridge!!)` after `nfbCalibratorBridge`. Add its stream handlers to the `streamHandlerMap` `buildMap` block:
     ```kotlin
     for ((id, handler) in emotionsBridge!!.allStreamHandlers()) {
         put(id, handler)
     }
     ```

  3. **`handleEmotionsCall`** — replace the `result.notImplemented()` stub with the full implementation. Pattern mirrors `handleNfbCall`:
     ```kotlin
     val bridge = emotionsBridge
         ?: return result.error("NOT_INITIALIZED", "EmotionsBridge not initialized", null)
     val devBridge = deviceBridge
         ?: return result.error("NOT_INITIALIZED", "DeviceBridge not initialized", null)
     try {
         when (call.method) {
             "create" -> {
                 val deviceHandle = devBridge.requireHandle()
                 bridge.create(deviceHandle)
                 result.success(null)
             }
             "dispose" -> {
                 bridge.dispose()
                 result.success(null)
             }
             else -> result.notImplemented()
         }
     } catch (e: FlutterError) {
         result.error(e.code, e.message, e.details)
     } catch (e: Exception) {
         result.error("UNKNOWN", e.message, null)
     }
     ```

  4. **`onDetachedFromEngine`** — add `emotionsBridge?.dispose()` and `emotionsBridge = null` before `deviceLocatorBridge?.dispose()`. Teardown order: classifiers before device, device before locator.
