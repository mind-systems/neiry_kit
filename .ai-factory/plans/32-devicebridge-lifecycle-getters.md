# Plan: DeviceBridge — lifecycle + getters

## Context
Implements the Android JNI + Kotlin bridge for device lifecycle commands (`connect`, `disconnect`, `start`, `stop`) and all device getters (`getBatteryCharge`, `getMode`, sample rates, PPG amplitudes, channel names). This is the Android counterpart of the already-complete iOS `DeviceBridge.swift`, following the same handle management, error propagation, and method dispatch patterns established by `DeviceLocatorBridge`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI layer (`jni_device.cpp`)

- [x] **Task 1: Create `jni_device.cpp` with lifecycle functions**
  Files: `android/src/main/cpp/jni_device.cpp`, `android/src/main/cpp/jni_device_locator.cpp`
  Create a new C++ file mirroring the structure of `jni_device_locator.cpp`. Implement these JNI functions (all under `extern "C"`):
  - `nativeConnectDevice(JNIEnv*, jobject, jlong handle, jboolean bipolarChannels)` — casts `handle` via `(clCDevice)(uintptr_t)handle`, calls `clCDevice_Connect(dev, (bool)bipolarChannels, &error)`, throws via `throw_sdk_error` on failure.
  - `nativeDisconnectDevice(JNIEnv*, jobject, jlong handle)` — calls `clCDevice_Disconnect(dev, &error)`.
  - `nativeStartDevice(JNIEnv*, jobject, jlong handle)` — calls `clCDevice_Start(dev, &error)`.
  - `nativeStopDevice(JNIEnv*, jobject, jlong handle)` — calls `clCDevice_Stop(dev, &error)`.
  - `nativeReleaseDevice(JNIEnv*, jobject, jlong handle)` — guard `handle == 0` → return; calls `clCDevice_Release(dev)`.
  All function names follow `Java_com_neiry_neiry_1kit_NativeBridge_<name>`. Reuse `throw_sdk_error` from `jni_device_locator.cpp` via `extern` declaration: add `extern void throw_sdk_error(JNIEnv* env, const clCError* error);` at the top of `jni_device.cpp`. **Important:** `throw_sdk_error` is currently declared `static` in `jni_device_locator.cpp` (line 23), which gives it internal linkage — the `extern` will cause a linker error. Remove the `static` keyword from the definition in `jni_device_locator.cpp` so the function is visible across translation units.

- [x] **Task 2: Add getter JNI functions to `jni_device.cpp`**
  Files: `android/src/main/cpp/jni_device.cpp`
  Add these JNI functions to the same file:
  - `nativeGetBatteryCharge(jlong handle)` → `jint` — calls `clCDevice_GetBatteryCharge(dev, &error)`, returns `(jint)result`.
  - `nativeGetMode(jlong handle)` → `jint` — calls `clCDevice_GetMode(dev)` (NO `clCError*` param, no error check), returns `(jint)result`. If `handle == 0`, return `-1`.
  - `nativeGetEEGSampleRate(jlong handle)` → `jfloat` — calls `clCDevice_GetEEGSampleRate(dev, &error)`.
  - `nativeGetPPGSampleRate(jlong handle)` → `jfloat` — calls `clCDevice_GetPPGSampleRate(dev, &error)`.
  - `nativeGetMEMSSampleRate(jlong handle)` → `jfloat` — calls `clCDevice_GetMEMSSampleRate(dev, &error)`.
  - `nativeGetPPGIrAmplitude(jlong handle)` → `jint` — calls `clCDevice_GetPPGIrAmplitude(dev, &error)`, returns `(jint)result`.
  - `nativeGetPPGRedAmplitude(jlong handle)` → `jint` — calls `clCDevice_GetPPGRedAmplitude(dev, &error)`, returns `(jint)result`.
  All except `nativeGetMode` follow the pattern: cast handle, `clCError error = {}`, call SDK, `if (!error.success) { throw_sdk_error(env, &error); return 0; }`, return value.

- [x] **Task 3: Add channel name JNI functions to `jni_device.cpp`**
  Files: `android/src/main/cpp/jni_device.cpp`
  Implement the two-step `clCDevice_GetChannelNames` handle pattern:
  - `nativeGetChannelNames(jlong deviceHandle)` → `jobject` (ArrayList of Strings) — calls `clCDevice_GetChannelNames(dev, &error)` to get the names handle, then `clCDevice_ChannelNames_GetChannelsCount(names, &error)`, then loops calling `clCDevice_ChannelNames_GetChannelNameByIndex(names, i, &error)`. Build a `java.util.ArrayList` with `env->NewStringUTF(name)` per entry. Clean up all local refs. Note: there is no release function for the channel names handle.
  - `nativeGetChannelsCount(jlong deviceHandle)` → `jint` — same two-step: get names handle, get count.
  - `nativeGetChannelIndexByName(jlong deviceHandle, jstring channelName)` → `jint` — get names handle, call `clCDevice_ChannelNames_GetChannelIndexByName(names, nameStr, &error)`, release UTF chars.
  - `nativeGetChannelNameByIndex(jlong deviceHandle, jint index)` → `jstring` — get names handle, call `clCDevice_ChannelNames_GetChannelNameByIndex(names, (int32_t)index, &error)`, return `env->NewStringUTF(result)`.
  - `nativeGetRawChannelNamesHandle(jlong deviceHandle)` → `jlong` — calls `clCDevice_GetChannelNames(dev, &error)`, returns `(jlong)(uintptr_t)handle`. This is used by the Kotlin layer for caching (see Task 6).
  - `nativeGetChannelsCountFromHandle(jlong namesHandle)` → `jint` — calls `clCDevice_ChannelNames_GetChannelsCount` on the given names handle.
  - `nativeGetChannelNameByIndexFromHandle(jlong namesHandle, jint index)` → `jstring` — calls `clCDevice_ChannelNames_GetChannelNameByIndex` on the given names handle.
  - `nativeGetChannelIndexByNameFromHandle(jlong namesHandle, jstring channelName)` → `jint` — calls `clCDevice_ChannelNames_GetChannelIndexByName` on the given names handle.
  The high-level functions (`nativeGetChannelNames`, `nativeGetChannelsCount`, `nativeGetChannelIndexByName`, `nativeGetChannelNameByIndex`) each get their own names handle internally. The `*FromHandle` variants accept an externally provided handle — the Kotlin layer uses these with a cached handle to avoid leaking handles on repeated calls (there is no release function for the channel names handle; iOS caches in `getOrCacheChannelNamesHandle()` and Android must do the same).

- [x] **Task 4: Register `jni_device.cpp` in CMakeLists.txt**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_device.cpp` to the `add_library(neiry_jni SHARED ...)` source list, after `jni_device_locator.cpp`.

### Phase 2: Kotlin layer

- [x] **Task 5: Add device `external fun` declarations to `NativeBridge.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Add a `// ── Device ──` section after the device locator section with these declarations:
  ```
  external fun nativeConnectDevice(handle: Long, bipolarChannels: Boolean)
  external fun nativeDisconnectDevice(handle: Long)
  external fun nativeStartDevice(handle: Long)
  external fun nativeStopDevice(handle: Long)
  external fun nativeReleaseDevice(handle: Long)
  external fun nativeGetBatteryCharge(handle: Long): Int
  external fun nativeGetMode(handle: Long): Int
  external fun nativeGetEEGSampleRate(handle: Long): Float
  external fun nativeGetPPGSampleRate(handle: Long): Float
  external fun nativeGetMEMSSampleRate(handle: Long): Float
  external fun nativeGetPPGIrAmplitude(handle: Long): Int
  external fun nativeGetPPGRedAmplitude(handle: Long): Int
  external fun nativeGetChannelNames(handle: Long): List<String>
  external fun nativeGetChannelsCount(handle: Long): Int
  external fun nativeGetChannelIndexByName(handle: Long, channelName: String): Int
  external fun nativeGetChannelNameByIndex(handle: Long, index: Int): String
  external fun nativeGetRawChannelNamesHandle(handle: Long): Long
  external fun nativeGetChannelsCountFromHandle(namesHandle: Long): Int
  external fun nativeGetChannelNameByIndexFromHandle(namesHandle: Long, index: Int): String
  external fun nativeGetChannelIndexByNameFromHandle(namesHandle: Long, channelName: String): Int
  ```

- [x] **Task 6: Create `DeviceBridge.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt`
  Create a new Kotlin class mirroring the iOS `DeviceBridge.swift` structure. Constructor takes `nativeBridge: NativeBridge`. Instance state:
  - `handle: Long = 0L` — device handle from `DeviceLocatorBridge.devices`.
  - `serial: String? = null`.
  - `channelNamesHandle: Long = 0L` — cached channel names handle, mirroring iOS's `channelNamesHandle: OpaquePointer?`. There is no release function for this type, so it is cached to avoid leaking handles on repeated calls.

  Methods:
  - `setDevice(serial: String, handle: Long)` — if old handle exists and differs, call `nativeReleaseDevice(old)`; store new handle + serial. **Reset `channelNamesHandle = 0L`** when device changes (new device = new channel names handle needed).
  - `requireHandle(): Long` — returns `handle` or throws `FlutterError("NO_DEVICE", "No device handle — call createDevice first", null)`.
  - `getOrCacheChannelNamesHandle(): Long` — if `channelNamesHandle != 0L` return it. Otherwise call `requireHandle()`, then `nativeBridge.nativeGetRawChannelNamesHandle(handle)` in try/catch, store the result in `channelNamesHandle`, and return it. This mirrors iOS's `getOrCacheChannelNamesHandle()` pattern exactly.
  - `connect(bipolarChannels: Boolean)` — calls `requireHandle()`, wraps `nativeBridge.nativeConnectDevice(handle, bipolarChannels)` in `try/catch(RuntimeException)` → `throw parseSdkError(...)`.
  - `disconnect()` — same pattern with `nativeDisconnectDevice`.
  - `start()` — same pattern with `nativeStartDevice`.
  - `stop(): Boolean` — same pattern with `nativeStopDevice`, returns `true` on success.
  - `release()` — calls `nativeReleaseDevice(handle)` if `handle != 0L`, zeros handle, nulls serial, zeros `channelNamesHandle`.
  - `getBatteryCharge(): Int` — `requireHandle()` + try/catch `nativeGetBatteryCharge`.
  - `getMode(): Int` — NO `requireHandle()`, NO throw; if `handle == 0L` return `-1`, else return `nativeBridge.nativeGetMode(handle)`. Matches iOS behavior.
  - `getEEGSampleRate(): Float`, `getPPGSampleRate(): Float`, `getMEMSSampleRate(): Float` — `requireHandle()` + try/catch pattern.
  - `getPPGIrAmplitude(): Int`, `getPPGRedAmplitude(): Int` — `requireHandle()` + try/catch pattern.
  - `getChannelNames(): List<String>` — calls `getOrCacheChannelNamesHandle()`, then uses `nativeGetChannelsCountFromHandle` and `nativeGetChannelNameByIndexFromHandle` with the cached handle to build the list. Try/catch pattern.
  - `getChannelsCount(): Int` — calls `getOrCacheChannelNamesHandle()`, then `nativeGetChannelsCountFromHandle`. Try/catch pattern.
  - `getChannelIndexByName(channelName: String): Int` — calls `getOrCacheChannelNamesHandle()`, then `nativeGetChannelIndexByNameFromHandle`. Try/catch pattern.
  - `getChannelNameByIndex(index: Int): String` — calls `getOrCacheChannelNamesHandle()`, then `nativeGetChannelNameByIndexFromHandle`. Try/catch pattern.

  All try/catch blocks follow the established pattern from `DeviceLocatorBridge.kt`: `catch (e: RuntimeException) { throw parseSdkError(e.message ?: "255|Unknown error") }`.

- [x] **Task 7: Wire `DeviceBridge` into `NeiryKitPlugin.kt`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Three changes:
  1. Add `private var deviceBridge: DeviceBridge? = null` field. In `onAttachedToEngine`, create `deviceBridge = DeviceBridge(nativeBridge!!)` after `deviceLocatorBridge`.
  2. In `handleDeviceLocatorCall`, after `bridge.createDevice(serial)` succeeds (the existing `"createDevice"` case), add: look up `DeviceLocatorBridge.devices[serial]`, if found call `deviceBridge?.setDevice(serial, handle)` and remove from `devices`. This mirrors the iOS pattern at line 112–114.
  3. Replace the stub `handleDeviceCall` with a full implementation. Use the same `try/catch(FlutterError)/catch(Exception)` error handling as `handleDeviceLocatorCall`. Null-safe dispatch: `val bridge = deviceBridge ?: return result.error("NOT_INITIALIZED", "DeviceBridge not initialized", null)`. Method dispatch via `when(call.method)`:
     - `"connect"` → extract `bipolarChannels` as `Boolean` from args (default `false`), call `bridge.connect(bipolarChannels)`, `result.success(null)`.
     - `"disconnect"` → `bridge.disconnect()`, `result.success(null)`.
     - `"start"` → `bridge.start()`, `result.success(null)`.
     - `"stop"` → `result.success(bridge.stop())`.
     - `"getInfo"` → `result.notImplemented()` — deferred to a separate task. Note: `getInfo` is a device-level API (`clCDevice_GetInfo` takes a `clCDevice` handle), not a locator-level call.
     - `"getBatteryCharge"` → `result.success(bridge.getBatteryCharge())`.
     - `"getMode"` → `result.success(bridge.getMode())` — no try/catch needed (getMode never throws).
     - `"getEEGSampleRate"` → `result.success(bridge.getEEGSampleRate())`.
     - `"getPPGSampleRate"` → `result.success(bridge.getPPGSampleRate())`.
     - `"getMEMSSampleRate"` → `result.success(bridge.getMEMSSampleRate())`.
     - `"getPPGIrAmplitude"` → `result.success(bridge.getPPGIrAmplitude())`.
     - `"getPPGRedAmplitude"` → `result.success(bridge.getPPGRedAmplitude())`.
     - `"getChannelNames"` → `result.success(bridge.getChannelNames())`.
     - `"getChannelsCount"` → `result.success(bridge.getChannelsCount())`.
     - `"getChannelIndexByName"` → extract `channelName: String` from args, `result.success(bridge.getChannelIndexByName(channelName))`.
     - `"getChannelNameByIndex"` → extract `index: Int` from args, `result.success(bridge.getChannelNameByIndex(index))`.
     - `else` → `result.notImplemented()`.
     No `"release"` case — Dart's `DeviceMethods` class has no `release` method (device release happens via `Device.dispose()` which calls `disconnect`). Device handle release is triggered at the plugin level during engine detach and locator disposal, not through method channel dispatch.
  4. In `onDetachedFromEngine`, call `deviceLocatorBridge?.dispose()` first, then `deviceBridge?.release()` after — matching iOS disposal order (see `NeiryKitPlugin.swift:154-155` where `bridge.dispose()` runs before `deviceBridge?.release()`). Set `deviceBridge = null`.

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add JNI device lifecycle, getters, and channel name functions"
- **Commit 2** (after tasks 5-7): "Add Kotlin DeviceBridge with channel names caching and wire into plugin dispatch"
