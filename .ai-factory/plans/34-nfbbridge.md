# Plan: NfbBridge (Android)

## Context
Implement the Android-side NFB classifier bridge (`jni_nfb.cpp` + `NfbBridge.kt`) with two factory paths (plain and calibrated), two EventChannels (`nfbState`, `nfbError`), and all supporting infrastructure changes — mirroring the existing iOS `NfbBridge.swift`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Make map helpers and JNI caches shareable across translation units

- [x] **Task 1: Remove `static` from map helpers and cache vars in `jni_device.cpp`**
  Files: `android/src/main/cpp/jni_device.cpp`
  Remove the `static` keyword from all HashMap/boxing JNI cache variables (`s_hmClass`, `s_hmCtor`, `s_hmPut`, `s_intClass`, `s_intValueOf`, `s_longClass`, `s_longValueOf`, `s_floatClass`, `s_floatValueOf`, `s_doubleClass`, `s_doubleValueOf`, `s_boolClass`, `s_boolValueOf`, `s_stringClass`) and from all map helper functions (`init_map_cache`, `make_map`, `map_put_int`, `map_put_long`, `map_put_float`, `map_put_double`, `map_put_string`, `map_put_bool`, `map_put_object`). These become file-scope non-static so other translation units can `extern` them. The `DeviceSlot` struct, `g_device_slots`, `g_device_mutex`, device slot helpers (`find_device_slot`, `register_device_slot`, `unregister_device_slot`), and all device callback functions remain `static` — they are private to `jni_device.cpp`.

### Phase 2: JNI layer — `jni_nfb.cpp`

- [x] **Task 2: Create `jni_nfb.cpp` with globals and extern declarations** (depends on Task 1)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Create the file with includes (`jni.h`, `pthread.h`, `cstdio`, `CCapsuleAPI.h`) and extern declarations for shared globals from `jni_device_locator.cpp` (`g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`) and `jni_device.cpp` (`init_map_cache`, `make_map`, `map_put_float`, `map_put_long`, `map_put_string`), plus `throw_sdk_error`. Add file-private globals: `static jobject g_nfbStateSink = nullptr`, `static jobject g_nfbErrorSink = nullptr`, `static pthread_mutex_t g_nfb_mutex = PTHREAD_MUTEX_INITIALIZER`. Forward-declare two static callback functions: `on_nfb_state_changed` and `on_nfb_error`.

- [x] **Task 3: Implement `nativeCreateNfb` JNI function** (depends on Task 2)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateNfb(JNIEnv* env, jobject, jlong deviceHandle)`. Cast `deviceHandle` to `clCDevice` via `(clCDevice)(uintptr_t)`. Call `clCNFB_Create(dev, &error)`, throw via `throw_sdk_error` if `!error.success`. Store the returned `clCNFB` handle. Register callbacks: `clCNFB_SetOnUserStateChangedEvent(nfb, on_nfb_state_changed)` and `clCNFB_SetOnErrorEvent(nfb, on_nfb_error)`. Return the handle as `jlong`.

- [x] **Task 4: Implement `nativeCreateNfbCalibrated` JNI function** (depends on Task 2)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateNfbCalibrated(JNIEnv* env, jobject, jlong deviceHandle, jboolean hasCalibrationData, jlong ts, jint failReason, jfloat individualFrequency, jfloat individualPeakFrequency, jfloat individualPeakFrequencyPower, jfloat individualPeakFrequencySuppression, jfloat individualBandwidth, jfloat individualNormalizedPower, jfloat lowerFrequency, jfloat upperFrequency)`. Cast `deviceHandle` to `clCDevice`. Call `clCNFBCalibrator_CreateOrGet(dev)` — if the returned pointer is null, call `throw_sdk_error` with an encoded string `"0|clCNFBCalibrator_CreateOrGet returned null"` (using `ThrowNew` with `RuntimeException`) and return 0. If `hasCalibrationData` is true, populate a `clCIndividualNFBData` struct with all 10 fields (`timestampMilli`, `failReason` cast to `clCIndividualNFBCalibrationFailReason`, `individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`) and call `clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError)` — throw on failure. Call `clCNFB_CreateCalibrated(dev, calibrator, &error)`, throw on failure. Register callbacks (same as Task 3). Return handle as `jlong`.

- [x] **Task 5: Implement `nativeSetNfbStateSink` and `nativeSetNfbErrorSink` JNI functions** (depends on Task 2)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Two separate JNI functions (NOT one with streamType dispatch). `nativeSetNfbStateSink(jobject sink)`: mutex-lock `g_nfb_mutex`, delete old `g_nfbStateSink` global ref if non-null, set new global ref from `sink` (or nullptr), unlock. `nativeSetNfbErrorSink(jobject sink)`: same pattern for `g_nfbErrorSink`. Follow the exact pattern from `nativeSetDeviceStreamSink` in `jni_device.cpp`.

- [x] **Task 6: Implement `nativeDisposeNfb` JNI function** (depends on Task 2)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Implement `Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeNfb(JNIEnv* env, jobject, jlong nfbHandle)`. If `nfbHandle == 0` return. Cast to `clCNFB`. Null out both callbacks: `clCNFB_SetOnUserStateChangedEvent(nfb, nullptr)`, `clCNFB_SetOnErrorEvent(nfb, nullptr)`. Mutex-lock `g_nfb_mutex`, delete global refs for both sinks if non-null and set to nullptr, unlock. There is no `clCNFB_Destroy` — only callback unregistration and sink cleanup.

- [x] **Task 7: Implement `on_nfb_state_changed` callback** (depends on Tasks 2, 5)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Static callback `void on_nfb_state_changed(clCNFB nfb, const clCNFB_UserState* data) noexcept`. Follow the `goto cleanup` pattern from `jni_device.cpp` callbacks: early-return if `!g_jvm` or `!data`; attach thread if needed; mutex-lock `g_nfb_mutex`, create local refs from `g_nfbStateSink` and `g_handler` via `NewLocalRef`, unlock; if either is null, goto cleanup; build map with `make_map` and populate keys `"ts"` (long, `data->timestampMilli`), `"delta"` (float), `"theta"` (float), `"alpha"` (float), `"smr"` (float), `"beta"` (float) — matching the iOS `NfbBridge.swift` map shape exactly; dispatch via `CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map)`; cleanup: delete local refs for map, sink_ref, handler_ref; `DetachCurrentThread` if attached.

- [x] **Task 8: Implement `on_nfb_error` callback** (depends on Tasks 2, 5)
  Files: `android/src/main/cpp/jni_nfb.cpp`
  Static callback `void on_nfb_error(clCNFB nfb, const char* message) noexcept`. Same `goto cleanup` pattern. Build map with single key `"message"` (string, from `message` param). Dispatch via `g_postSuccess` to `g_nfbErrorSink`. Matches iOS `NfbBridge.swift` error handler which sends `["message": message]`.

### Phase 3: Build system

- [x] **Task 9: Add `jni_nfb.cpp` to CMakeLists.txt** (depends on Task 2)
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_nfb.cpp` to the `add_library(neiry_jni SHARED ...)` source list alongside the existing `jni_bridge.cpp`, `jni_device_locator.cpp`, `jni_device.cpp`.

### Phase 4: Kotlin bridge layer

- [x] **Task 10: Add NFB `external fun` declarations to `NativeBridge.kt`** (depends on Tasks 3-6)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a new `// ── NFB classifier ──` section with: `external fun nativeCreateNfb(deviceHandle: Long): Long`, `external fun nativeCreateNfbCalibrated(deviceHandle: Long, hasCalibrationData: Boolean, ts: Long, failReason: Int, individualFrequency: Float, individualPeakFrequency: Float, individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float, individualBandwidth: Float, individualNormalizedPower: Float, lowerFrequency: Float, upperFrequency: Float): Long`, `external fun nativeSetNfbStateSink(sink: EventChannel.EventSink?)`, `external fun nativeSetNfbErrorSink(sink: EventChannel.EventSink?)`, `external fun nativeDisposeNfb(nfbHandle: Long)`.

- [x] **Task 11: Create `NfbBridge.kt`** (depends on Task 10)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NfbBridge.kt`
  Create `NfbBridge` class taking `NativeBridge` constructor param. Private `var handle: Long = 0L`. Inner class `NfbStreamHandler(private val setSink: (EventChannel.EventSink?) -> Unit) : EventChannel.StreamHandler` — `onListen` calls `setSink(events)`, `onCancel` calls `setSink(null)`. Create two handlers: `val nfbStateHandler = NfbStreamHandler { nativeBridge.nativeSetNfbStateSink(it) }` and `val nfbErrorHandler = NfbStreamHandler { nativeBridge.nativeSetNfbErrorSink(it) }`. Public `fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>>` returning `"neiry_kit/events/nfbState"` and `"neiry_kit/events/nfbError"` pairs. Public `fun create(deviceHandle: Long)` — disposes old handle if non-zero, calls `nativeBridge.nativeCreateNfb(deviceHandle)`, stores result, wraps `RuntimeException` with `parseSdkError()`. Public `fun createCalibrated(deviceHandle: Long, calibrationData: Map<String, Any>?)` — disposes old handle, extracts all 10 fields from the map (with defaults), calls `nativeBridge.nativeCreateNfbCalibrated(...)`, stores result. Public `fun dispose()` — calls `nativeBridge.nativeDisposeNfb(handle)` if `handle != 0L`, sets `handle = 0L`.

### Phase 5: Plugin wiring

- [x] **Task 12: Wire NfbBridge into NeiryKitPlugin.kt** (depends on Task 11)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Add `private var nfbBridge: NfbBridge? = null`. In `onAttachedToEngine`, after `deviceBridge` creation, instantiate `nfbBridge = NfbBridge(nativeBridge!!)`. In the `streamHandlerMap` builder, add `for ((id, handler) in nfbBridge!!.allStreamHandlers()) { put(id, handler) }` — this replaces the `StubStreamHandler` for `nfbState` and `nfbError` channels. Implement `handleNfbCall`: guard `val bridge = nfbBridge ?: return result.error(...)` and `val devBridge = deviceBridge ?: return result.error(...)`. Switch on `call.method`: `"create"` — get `deviceHandle` from `devBridge` (add `fun requireHandle(): Long` as a public accessor, or use the existing handle field — follow iOS pattern where `handleNfbCall` calls `deviceBridge.requireDevice()`), call `bridge.create(deviceHandle)`, return `result.success(null)`; `"createCalibrated"` — extract `calibrationData` map from `call.arguments`, call `bridge.createCalibrated(deviceHandle, calibrationData)`, return `result.success(null)`; `"dispose"` — call `bridge.dispose()`, return `result.success(null)`. Wrap in try/catch for `FlutterError` and `Exception`, matching the pattern from `handleDeviceCall`. Update teardown in `onDetachedFromEngine`: add `nfbBridge?.dispose()` **before** `deviceLocatorBridge?.dispose()` and `deviceBridge?.release()` — classifiers must be torn down first, matching iOS teardown order (nfb before device locator and device). Set `nfbBridge = null` after dispose. Also expose device handle from `DeviceBridge` — add `fun requireHandle(): Long` (make the existing private `requireHandle()` public or add a new public method) so the plugin can pass it to classifier bridges.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Remove static from JNI map helpers and create jni_nfb.cpp skeleton"
- **Commit 2** (after tasks 3-8): "Implement all JNI functions and callbacks for NfbBridge"
- **Commit 3** (after tasks 9-12): "Wire NfbBridge into build system, Kotlin layer, and plugin dispatch"
