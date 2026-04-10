# Plan: DeviceBridge — streams

## Context

Implement the Android JNI side of 8 device EventChannel streams (eeg, psd, artifacts, resistance, battery, error, connectionStatus, mode). The C SDK fires callbacks on background threads with no context parameter, so a static device registry keyed by `clCDevice` pointer resolves which sinks to emit to. All emissions are marshaled to HashMaps and dispatched to the main thread via `SinkDispatcher.postSuccess`. Map keys and error-handling policy match the iOS `DeviceBridge.swift` implementation exactly.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Infrastructure

- [x] **Task 1: JNI device stream infrastructure**
  Files: `android/src/main/cpp/jni_device_locator.cpp`, `android/src/main/cpp/jni_device.cpp`
  First, in `jni_device_locator.cpp`, remove `static` from 4 global declarations so they have external linkage and can be shared with `jni_device.cpp`: `g_jvm` (line 8), `g_handler` (line 9), `g_dispatcher_class` (line 16), `g_postSuccess` (line 17). These are currently `static` which gives them internal linkage — `extern` declarations in another translation unit would cause a linker error. `g_deviceListSink`, `g_callback_mutex`, `g_postError`, and `g_postEndOfStream` stay `static` (not needed outside this file).
  Then, add all stream infrastructure to `jni_device.cpp`, above the `extern "C"` block for existing JNI functions:
  - **Extern declarations** for the 4 shared globals now with external linkage in `jni_device_locator.cpp`: `extern JavaVM* g_jvm`, `extern jobject g_handler`, `extern jclass g_dispatcher_class`, `extern jmethodID g_postSuccess`. Follow the existing `extern void throw_sdk_error(...)` precedent already at the top of the file.
  - **Stream type enum** — `enum DeviceStream { STREAM_EEG = 0, STREAM_PSD, STREAM_ARTIFACTS, STREAM_RESISTANCE, STREAM_BATTERY, STREAM_ERROR, STREAM_CONNECTION_STATUS, STREAM_MODE, STREAM_COUNT };` (STREAM_COUNT = 8, used for array sizing).
  - **Device registry** — `#define MAX_DEVICES 4`; a struct `DeviceSlot` with fields `clCDevice device` and `jobject sinks[STREAM_COUNT]`; a static array `g_device_slots[MAX_DEVICES]` zero-initialized; helper functions `find_device_slot(clCDevice)` returning index or -1, `register_device_slot(clCDevice)` returning index or -1, `unregister_device_slot(JNIEnv*, int slot)` clearing device pointer and deleting all sink global refs under mutex.
  - **Mutex** — `static pthread_mutex_t g_device_mutex = PTHREAD_MUTEX_INITIALIZER;` guards all sink global refs in the registry.
  - **HashMap helpers** — static functions for building Java HashMap objects via JNI: `make_map(env)` returns a new `java/util/HashMap`; `map_put_int(env, map, key, val)`, `map_put_long(env, map, key, val)`, `map_put_float(env, map, key, val)`, `map_put_double(env, map, key, val)`, `map_put_string(env, map, key, val)`, `map_put_bool(env, map, key, val)`. Each creates a boxed value (`Integer.valueOf`, `Long.valueOf`, etc.), calls `map.put(key, value)`, and deletes local refs for the key string and boxed value. Cache `HashMap` class/method IDs and boxed-type method IDs at first call (static locals).
  - **Forward declarations** for all 8 callback functions: `on_eeg_data`, `on_psd_data`, `on_artifacts_data`, `on_resistance_data`, `on_battery_data`, `on_error_data`, `on_connection_status_changed`, `on_mode_switched`. Each matches the C SDK callback typedef signature exactly — see `CDevice.h`.
  - **JNI function `nativeRegisterDeviceCallbacks(jlong handle)`** — cast handle to `clCDevice`, call `register_device_slot(dev)`, then call all 8 `clCDevice_SetOn*Event(dev, callback)` functions: `SetOnEEGDataEvent`, `SetOnPSDDataEvent`, `SetOnEEGArtifactsEvent`, `SetOnResistanceUpdateEvent`, `SetOnBatteryChargeUpdateEvent`, `SetOnErrorEvent`, `SetOnConnectionStatusChangedEvent`, `SetOnModeSwitchedEvent`.
  - **JNI function `nativeUnregisterDeviceCallbacks(jlong handle)`** — cast handle, find slot, call all 8 `SetOn*Event(dev, nullptr)` to clear callbacks, then `unregister_device_slot(env, slot)` which deletes all sink global refs under mutex and zeros the slot.
  - **JNI function `nativeSetDeviceStreamSink(jint streamType, jobject sink)`** — validate `streamType` in range `[0, STREAM_COUNT)`. Lock mutex. For the **first registered device slot** (slot 0 — plugin supports one device at a time), delete old global ref if non-null, then `NewGlobalRef(sink)` if sink is non-null (or null if clearing). Unlock mutex. This mirrors the `nativeSetDeviceListSink` pattern in `jni_device_locator.cpp`.

- [x] **Task 2: Kotlin stream handler plumbing** (depends on Task 1)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`, `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt`, `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  - **NativeBridge.kt** — add 3 declarations in the `// ── Device` section:
    ```kotlin
    external fun nativeRegisterDeviceCallbacks(handle: Long)
    external fun nativeUnregisterDeviceCallbacks(handle: Long)
    external fun nativeSetDeviceStreamSink(streamType: Int, sink: EventChannel.EventSink?)
    ```
  - **DeviceBridge.kt** — add an inner class `DeviceStreamHandler(private val nativeBridge: NativeBridge, private val streamType: Int) : EventChannel.StreamHandler` with `onListen` calling `nativeBridge.nativeSetDeviceStreamSink(streamType, events)` and `onCancel` calling `nativeBridge.nativeSetDeviceStreamSink(streamType, null)`. Add companion constants matching the C enum: `STREAM_EEG = 0`, ..., `STREAM_MODE = 7`. Create 8 `DeviceStreamHandler` instances as `val` properties: `eegHandler`, `psdHandler`, `artifactsHandler`, `resistanceHandler`, `batteryHandler`, `errorHandler`, `connectionStatusHandler`, `modeHandler`. Add `fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>>` returning pairs of `(channelId, handler)` — channel IDs are `"neiry_kit/events/eeg"`, `"neiry_kit/events/psd"`, `"neiry_kit/events/eegArtifacts"`, `"neiry_kit/events/resistance"`, `"neiry_kit/events/battery"`, `"neiry_kit/events/error"`, `"neiry_kit/events/connectionStatus"`, `"neiry_kit/events/modeSwitched"`. Modify `setDevice()`: in the `old != 0L && old != handle` branch, call `nativeBridge.nativeUnregisterDeviceCallbacks(old)` **before** `nativeBridge.nativeReleaseDevice(old)` (unregister callbacks first to prevent use-after-free — matches iOS `DeviceBridge.swift` line 113 which calls `unregisterCallbacks()` before `clCDevice_Release(old)`). After storing the new handle, call `nativeBridge.nativeRegisterDeviceCallbacks(handle)`. Modify `release()` to call `nativeBridge.nativeUnregisterDeviceCallbacks(handle)` **before** `nativeReleaseDevice(handle)` (callbacks must be torn down before the device handle is released).
  - **NeiryKitPlugin.kt** — in the EventChannel registration loop inside `onAttachedToEngine`, build a `Map<String, EventChannel.StreamHandler>` from `deviceBridge!!.allStreamHandlers()` and merge with the existing `deviceLocatorBridge!!` entry. Replace the `when` block: look up the channel ID in the merged map, fall back to `StubStreamHandler()` if not found. This replaces the 8 `StubStreamHandler` instances with the real device stream handlers.

### Phase 2: Simple callbacks

- [x] **Task 3: Battery, error, connectionStatus, mode callbacks** (depends on Task 1)
  Files: `android/src/main/cpp/jni_device.cpp`
  Implement 4 callback functions using a shared `goto cleanup` pattern. Each callback follows this skeleton:
  1. Early-return if `g_jvm` is null.
  2. `GetEnv` / `AttachCurrentThread` — set `bool attached = false`.
  3. `find_device_slot(device)` — if slot < 0, `goto cleanup`.
  4. Lock `g_device_mutex`, `NewLocalRef` the sink for the appropriate stream type and `g_handler`, unlock.
  5. If sink or handler ref is null, `goto cleanup`.
  6. Build map, call `env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map)`.
  7. `cleanup:` label — delete local refs (map, sink_ref, handler_ref) if non-null; `DetachCurrentThread` if `attached`.
  Specific callbacks:
  - **`on_battery_data(clCDevice, uint8_t charge)`** — map: `{"charge": (int)charge}`.
  - **`on_error_data(clCDevice, const char* message)`** — map: `{"message": message}` (use `""` if null).
  - **`on_connection_status_changed(clCDevice, clCDevice_ConnectionStatus status)`** — map: `{"state": (int)status}`.
  - **`on_mode_switched(clCDevice, clCDevice_Mode mode)`** — map: `{"mode": (int)mode}`.
  All match the iOS `DeviceBridge.swift` map keys exactly.

### Phase 3: Data-heavy callbacks

- [x] **Task 4: EEG callback** (depends on Task 1)
  Files: `android/src/main/cpp/jni_device.cpp`
  Implement `on_eeg_data(clCDevice, clCEEGTimedData data)` with `goto cleanup`:
  - Call `clCEEGTimedData_GetChannelsCount(data, &error)` and `clCEEGTimedData_GetSamplesCount(data, &error)` — `goto cleanup` on any error.
  - Call `clCEEGTimedData_GetTimestampMilli(data, 0, &error)` for the timestamp of sample 0 — `goto cleanup` on error. The timestamp is `uint64_t` — use `map_put_long` with `(jlong)ts` (bit-reinterpret same as iOS `Int64(bitPattern:)`).
  - Build 2D Java arrays `float[][]` for `rawValues` and `processedValues`: outer dimension = channels, inner = samples. Use `env->NewFloatArray(sampleCount)` per channel, fill via `SetFloatArrayRegion` from a stack/heap buffer populated by calling `GetRawValue(data, ch, s, &error)` / `GetProcessedValue(data, ch, s, &error)`. On any accessor error, `goto cleanup` (drop entire event, matching iOS behavior).
  - Map keys: `"ts"` (long), `"rawValues"` (float[][]), `"processedValues"` (float[][]), `"channelCount"` (int), `"sampleCount"` (int). Use `map.put` for the 2D array objects directly (put takes Object — `jobjectArray` is a jobject).
  - Clean up all intermediate local refs (inner arrays, the two outer `jobjectArray`s) in `cleanup:`.

- [x] **Task 5: PSD callback** (depends on Task 1)
  Files: `android/src/main/cpp/jni_device.cpp`
  Implement `on_psd_data(clCDevice, clCPSDData data)` with `goto cleanup`. This is the most complex callback — 19 map keys:
  - **Base data**: `GetTimestampMilli` (long), `GetFrequenciesCount`, `GetChannelsCount`. All take `clCError*` — `goto cleanup` on error.
  - **Frequency array**: `double[]` of size `frequencyCount`, each element from `GetFrequency(data, i, &error)`. On error, `goto cleanup`.
  - **PSD values**: `double[][]` — outer = channels, inner = frequencies. Each element from `GetPSD(data, ch, freq, &error)`. Use `NewDoubleArray` + `SetDoubleArrayRegion`. On error, `goto cleanup`.
  - **Band bounds**: loop over 5 bands `{Delta, Theta, Alpha, SMR, Beta}` with corresponding name prefixes `{"delta", "theta", "alpha", "smr", "beta"}`. For each band, call `GetBandLower(data, band, &error)` and `GetBandUpper(data, band, &error)`. On error, `goto cleanup`. Produces 10 map keys: `"deltaLower"`, `"deltaUpper"`, ..., `"betaUpper"`.
  - **Individual alpha**: call `HasIndividualAlpha(data, &error)` — **if the check itself fails (`!error.success`), `goto cleanup`** (hard bail). If returns true, call `GetIndividualAlphaLower` and `GetIndividualAlphaUpper` with `clCError*` — if accessor fails, emit `(float)-1` (soft error, not a bail). If returns false, emit `-1` for both. Keys: `"individualAlphaLower"`, `"individualAlphaUpper"`.
  - **Individual beta**: identical pattern. Keys: `"individualBetaLower"`, `"individualBetaUpper"`.
  - Map keys: `"ts"`, `"values"`, `"frequencies"`, `"channelCount"`, `"frequencyCount"`, 10 band keys, 4 individual keys — 19 total, always present.

- [x] **Task 6: Artifacts and resistance callbacks** (depends on Task 1)
  Files: `android/src/main/cpp/jni_device.cpp`
  Implement 2 callbacks:
  - **`on_artifacts_data(clCDevice, clCEEGArtifacts data)`** with `goto cleanup`:
    - `GetTimestampMilli(data, &error)`, `GetChannelsCount(data, &error)` — `goto cleanup` on error.
    - Per-channel loop: `GetArtifactByChannel(data, ch, &error)` (uint8_t → int) and `GetEEGQuality(data, ch, &error)` (float). On any error, `goto cleanup`.
    - Build Java `int[]` for artifacts and `float[]` for qualities via `NewIntArray`/`NewFloatArray` + `SetRegion`.
    - Map keys: `"ts"` (long), `"artifacts"` (int[]), `"qualities"` (float[]), `"channelCount"` (int).
  - **`on_resistance_data(clCDevice, clCResistance data)`** with `goto cleanup`:
    - `clCResistance_GetCount(data)` — **no `clCError*`** parameter, returns count directly.
    - Per-entry loop: `GetChannelName(data, i)` (const char*, use `""` if null) and `GetValue(data, i)` (float) — **no `clCError*`** on any resistance accessor.
    - Build Java `String[]` (`jobjectArray` of `java/lang/String`) for channel names and `float[]` for values.
    - Map keys: `"channelNames"` (String[]), `"values"` (float[]), `"channelCount"` (int).

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add device stream infrastructure and simple stream callbacks for Android"
- **Commit 2** (after tasks 4-6): "Add EEG, PSD, artifacts, and resistance stream callbacks for Android"
