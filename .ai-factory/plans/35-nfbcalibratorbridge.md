# Plan: NfbCalibratorBridge (Android)

## Context
Implement the Android JNI + Kotlin bridge for the `clCNFBCalibrator` C API — full 4-stage calibration with manual stage advancement, quick mode, import/export, and state queries. Mirrors the existing iOS `NfbCalibratorBridge.swift` and follows the JNI patterns established by `jni_nfb.cpp` + `NfbBridge.kt`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Build infrastructure

- [x] **Task 1: Make `g_postError` non-static and add new source to CMakeLists**
  Files: `android/src/main/cpp/jni_device_locator.cpp`, `android/src/main/cpp/CMakeLists.txt`
  In `jni_device_locator.cpp` line 18, remove the `static` keyword from `g_postError` so it has external linkage — the calibrator's stage-finished callback needs to dispatch stream errors via `SinkDispatcher.postError` when a mid-calibration SDK re-entry call fails (matching iOS `calibrationHandler.sendError(...)`). Only `g_postError` needs this change; `g_postEndOfStream` is not required.
  In `CMakeLists.txt`, append `jni_nfb_calibrator.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_nfb.cpp`.

### Phase 2: JNI implementation

- [x] **Task 2: Create `jni_nfb_calibrator.cpp`** (depends on Task 1)
  Files: `android/src/main/cpp/jni_nfb_calibrator.cpp`
  Create the full JNI implementation for `clCNFBCalibrator`. Follow `jni_nfb.cpp` structure exactly. The file has four sections:

  **Extern declarations** — declare all shared globals and helpers as `extern`, do NOT redefine:
  - From `jni_device_locator.cpp`: `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`, `g_postError` (newly non-static from Task 1).
  - From `jni_device.cpp`: `init_map_cache`, `make_map`, `map_put_int`, `map_put_float`, `map_put_long`, `map_put_string`, `map_put_object`.
  - From `jni_device_locator.cpp`: `throw_sdk_error`.

  **File-static calibrator state** — these are private to this file:
  - `g_calibrator: clCNFBCalibrator` — cached handle from `CreateOrGet`. Never destroyed (SDK manages lifecycle).
  - `g_currentStage: int` — 0-indexed, incremented on each stage-finished callback. Reset to 0 on start/stop.
  - `g_isQuickMode: bool` — set on start, used to guard stage advancement in callback.
  - `g_calibrationSink: jobject` — GlobalRef to EventSink, mutex-guarded.
  - `g_cal_mutex: pthread_mutex_t` — initialized with `PTHREAD_MUTEX_INITIALIZER`.

  **Two C callbacks:**

  `on_calibration_stage_finished(clCNFBCalibrator)`:
  - Early return if `g_isQuickMode` is true (quick mode never advances stages).
  - Attach thread, NewLocalRef snapshot of `g_calibrationSink` and `g_handler` under mutex.
  - Build map: `{"type": "stage", "stage": g_currentStage}` using `map_put_string` for "type" and `map_put_int` for "stage".
  - `CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map)`.
  - Increment `g_currentStage`.
  - If `g_currentStage < 4`: call `clCNFBCalibrator_CalibrateIndividualNFB(g_calibrator, (clCIndividualNFBCalibrationStage)g_currentStage, &error)`. If error, dispatch via `g_postError` with `code=String(error.code)`, `message=error.message` — this terminates the EventChannel stream on the Dart side. Construct the code and message as jstring objects for the `CallStaticVoidMethod` call.
  - `goto cleanup` with `DetachCurrentThread` on all paths.

  `on_calibrated(clCNFBCalibrator, const clCIndividualNFBData* data)`:
  - Attach thread, NewLocalRef snapshot under mutex.
  - Build inner `dataMap` with all 10 fields: `ts` (long), `failReason` (int, cast from `clCIndividualNFBCalibrationFailReason`), 8 float fields (`individualFrequency`, `individualPeakFrequency`, `individualPeakFrequencyPower`, `individualPeakFrequencySuppression`, `individualBandwidth`, `individualNormalizedPower`, `lowerFrequency`, `upperFrequency`).
  - Build outer map: `{"type": "done", "data": dataMap}` using `map_put_string` for "type" and `map_put_object` for "data".
  - Post via `g_postSuccess`.
  - `goto cleanup` with `DetachCurrentThread` on all paths.

  **Six JNI functions** (all `extern "C"`, mangled as `Java_com_neiry_neiry_1kit_NativeBridge_native*`):

  `nativeStartCalibration(jlong deviceHandle, jboolean quick)`:
  - Cast device handle: `clCDevice dev = (clCDevice)(uintptr_t)deviceHandle`.
  - `clCNFBCalibrator cal = clCNFBCalibrator_CreateOrGet(dev)` — null-check: if null, `ThrowNew(RuntimeException, "0|clCNFBCalibrator_CreateOrGet returned null")` and return.
  - Store `g_calibrator = cal`, `g_currentStage = 0`, `g_isQuickMode = (bool)quick`.
  - Register both callbacks via `clCNFBCalibrator_SetOnCalibrationStageFinishedEvent` and `clCNFBCalibrator_SetOnCalibratedEvent`.
  - If quick: call `clCNFBCalibrator_CalibrateIndividualNFBQuick(cal, &error)`. Else: call `clCNFBCalibrator_CalibrateIndividualNFB(cal, clCIndividualNFBCalibrationStage_1, &error)`. Check error with `throw_sdk_error`.

  `nativeStopCalibration()`:
  - If `g_calibrator` is non-null: `SetOnCalibrationStageFinishedEvent(g_calibrator, nullptr)` and `SetOnCalibratedEvent(g_calibrator, nullptr)`.
  - Reset `g_currentStage = 0`, `g_isQuickMode = false`.
  - Do NOT null `g_calibrator` — handle is SDK-managed, reused across calls.
  - Do NOT clear `g_calibrationSink` — the EventChannel sink lifecycle is managed by `nativeSetNfbCalibrationSink`.

  `nativeImportCalibration(jlong deviceHandle, jlong ts, jint failReason, jfloat×8)`:
  - `CreateOrGet` + null-check + throw pattern (same as `nativeCreateNfbCalibrated` in `jni_nfb.cpp`).
  - Populate `clCIndividualNFBData` struct with all 10 fields from JNI params.
  - Call `clCNFBCalibrator_ImportIndividualNFBData(cal, &data, &error)`, check with `throw_sdk_error`.

  `nativeGetCalibration(jlong deviceHandle)` → `jobject`:
  - `CreateOrGet` — if null, return `nullptr` (not an error, matches iOS returning nil).
  - `clCNFBCalibrator_IsCalibrated(cal)` — if false, return `nullptr`. **No error wrapping** (no `clCError*`).
  - `clCNFBCalibrator_GetIndividualNFB(cal, &data, &error)` — check with `throw_sdk_error`.
  - Build and return HashMap with all 10 fields using `make_map` + `map_put_*`.

  `nativeIsCalibrated(jlong deviceHandle)` → `jboolean`:
  - `CreateOrGet` — if null, return `JNI_FALSE`.
  - Return `clCNFBCalibrator_IsCalibrated(cal)`. **No error wrapping** (no `clCError*`).

  `nativeSetNfbCalibrationSink(jobject sink)`:
  - Identical mutex-guarded GlobalRef swap pattern from `nativeSetNfbStateSink` in `jni_nfb.cpp`: lock mutex, delete old GlobalRef if non-null, create new GlobalRef if sink non-null, unlock.

### Phase 3: Kotlin integration

- [x] **Task 3: Add calibrator `external fun` declarations to `NativeBridge.kt`** (depends on Task 2)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a new `// ── NFB calibrator ──` section after the NFB classifier section with these declarations:
  ```
  external fun nativeStartCalibration(deviceHandle: Long, quick: Boolean)
  external fun nativeStopCalibration()
  external fun nativeImportCalibration(
      deviceHandle: Long,
      ts: Long, failReason: Int,
      individualFrequency: Float, individualPeakFrequency: Float,
      individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float,
      individualBandwidth: Float, individualNormalizedPower: Float,
      lowerFrequency: Float, upperFrequency: Float,
  )
  external fun nativeGetCalibration(deviceHandle: Long): Map<String, Any>?
  external fun nativeIsCalibrated(deviceHandle: Long): Boolean
  external fun nativeSetNfbCalibrationSink(sink: EventChannel.EventSink?)
  ```

- [x] **Task 4: Create `NfbCalibratorBridge.kt`** (depends on Task 3)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NfbCalibratorBridge.kt`
  Create a new Kotlin bridge class mirroring `NfbBridge.kt` structure. Takes `NativeBridge` in constructor.

  **Stream handler:** Inner `CalibrationStreamHandler` class (same pattern as `NfbBridge.NfbStreamHandler`) wrapping `nativeSetNfbCalibrationSink`. Single handler instance `calibrationHandler`. `allStreamHandlers()` returns `["neiry_kit/events/nfbCalibration" to calibrationHandler]`.

  **Methods:**
  - `startCalibration(deviceHandle: Long, quick: Boolean)` — wraps `nativeBridge.nativeStartCalibration(deviceHandle, quick)` in try/catch `RuntimeException` → `parseSdkError`.
  - `stopCalibration()` — calls `nativeBridge.nativeStopCalibration()`. No try/catch needed (iOS `stopCalibration` has no error path).
  - `importCalibration(deviceHandle: Long, data: Map<String, Any>)` — unpack all 10 fields from map using `(data["key"] as? Number)?.toFloat() ?: 0f` pattern (same as `NfbBridge.createCalibrated`). Call `nativeBridge.nativeImportCalibration(...)`, wrap in try/catch → `parseSdkError`.
  - `getCalibration(deviceHandle: Long): Map<String, Any>?` — wrap `nativeBridge.nativeGetCalibration(deviceHandle)` in try/catch → `parseSdkError`. Returns null when not calibrated.
  - `isCalibrated(deviceHandle: Long): Boolean` — direct call to `nativeBridge.nativeIsCalibrated(deviceHandle)`. **No try/catch** — `IsCalibrated` has no error path.
  - `dispose()` — calls `stopCalibration()`.

- [x] **Task 5: Wire `NfbCalibratorBridge` into `NeiryKitPlugin.kt`** (depends on Task 4)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`

  **Field:** Add `private var nfbCalibratorBridge: NfbCalibratorBridge? = null` alongside existing bridge fields.

  **Init (onAttachedToEngine):** Instantiate `nfbCalibratorBridge = NfbCalibratorBridge(nativeBridge!!)` after `nfbBridge` creation. Add its stream handlers to `streamHandlerMap` via `for ((id, handler) in nfbCalibratorBridge!!.allStreamHandlers()) { put(id, handler) }`.

  **Method dispatch (handleNfbCalibratorCall):** Replace the `result.notImplemented()` stub with full dispatch. Get both `nfbCalibratorBridge` and `deviceBridge` with null-safe `NOT_INITIALIZED` guards. Wrap in try/catch `FlutterError` + generic `Exception`. Dispatch on `call.method`:
  - `"startCalibration"` — extract `calibratorData` from args: if value is `"quick"` string, call `bridge.startCalibration(deviceHandle, quick=true)`, else `bridge.startCalibration(deviceHandle, quick=false)`. Call `result.success(null)`.
  - `"stopCalibration"` — call `bridge.stopCalibration()`, `result.success(null)`.
  - `"importCalibration"` — extract `calibratorData` as `Map<String, Any>`, null-check with `INVALID_ARGS` error, call `bridge.importCalibration(deviceHandle, data)`, `result.success(null)`.
  - `"getCalibration"` — call `bridge.getCalibration(deviceHandle)`, `result.success(map)` (map can be null).
  - `"isCalibrated"` — call `bridge.isCalibrated(deviceHandle)`, `result.success(bool)`.
  - `else` → `result.notImplemented()`.

  **Teardown (onDetachedFromEngine):** Add `nfbCalibratorBridge?.dispose()` before `nfbBridge?.dispose()` (calibrator before classifier, matching iOS teardown order). Set `nfbCalibratorBridge = null`.

## Commit Plan
- **Commit 1** (after tasks 1-5): "Add Android NfbCalibratorBridge with JNI stage tracking, quick mode, and import/export"
