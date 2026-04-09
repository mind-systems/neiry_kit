# Plan: DeviceLocatorBridge (Android)

## Context
Implement the Android JNI + Kotlin bridge for the device locator — the first real native bridge on Android. This establishes the shared infrastructure (NativeBridge, FlutterError, parseSdkError, SinkDispatcher, JNI error encoding) that all subsequent Android bridges will reuse, plus the full device discovery flow (create locator, scan, receive device list via EventChannel, create device handle).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Shared infrastructure

- [x] **Task 1: FlutterError class + parseSdkError utility**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/FlutterError.kt`
  Create a shared `FlutterError.kt` file in the plugin package. Android's Flutter embedding has no throwable `FlutterError` equivalent (unlike iOS where `FlutterError` is an NSObject and can be made `Error`-conformant). Define:
  - `class FlutterError(val code: String, override val message: String, val details: Any?) : Exception(message)` — a simple `Exception` subclass that carries `code`/`message`/`details`, matching the shape of `result.error(code, message, details)`.
  - Top-level function `fun parseSdkError(encoded: String): FlutterError` — splits the JNI-encoded error string on the **first** `|` character. The C side encodes `clCError` as `"<code>|<message>"`. `parseSdkError` extracts the numeric code (left of `|`) and the human-readable message (right of `|`). Returns `FlutterError(code, message, null)`. If splitting fails (no `|` found), use code `"255"` (unknown) and the full string as message.
  This file is imported by every bridge class and by `NeiryKitPlugin.kt` for `catch (e: FlutterError) { result.error(e.code, e.message, e.details) }`.

- [x] **Task 2: NativeBridge class with device locator declarations + SinkDispatcher**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`
  Create a regular class (not singleton — instance-per-plugin to avoid state leaking across hot restarts). All `external fun` declarations for the entire plugin live here, per notes/11. For this milestone, add only the device locator methods:
  - `external fun nativeGetVersion(): String` — moved from `NeiryKitPlugin`. Returns SDK version string.
  - `external fun nativeCreateLocator(logDir: String?): Long` — creates `clCDeviceLocator`, returns `jlong` handle.
  - `external fun nativeDestroyLocator(handle: Long)` — calls `clCDeviceLocator_Destroy`.
  - `external fun nativeRequestDevices(handle: Long, deviceType: Int, searchTime: Int)` — registers C callback + starts BLE scan. Throws encoded error string on failure.
  - `external fun nativeSetDeviceListSink(sink: EventChannel.EventSink?)` — passes the `EventSink` (as `jobject`) to the C side. `null` clears it. Use the concrete `EventChannel.EventSink?` type (not `Any?`) for Kotlin-side type safety — the JNI side sees `jobject` regardless.
  - `external fun nativeCreateDevice(locatorHandle: Long, serial: String): Long` — calls `clCDeviceLocator_CreateDevice`, returns device handle as `jlong`. Throws encoded error string on failure.
  - `external fun nativeSetSingleThreaded(enabled: Boolean)` — calls `clCCapsule_SetSingleThreaded`.
  - `external fun nativeUpdate(handle: Long)` — calls `clCDeviceLocator_Update`.
  - `external fun nativeSetLogLevel(level: Int)` — calls `clCCapsule_SetLogLevel`.
  The `companion object { init { ... } }` block loads both native libraries (`CapsuleClient` then `neiry_jni`), moved from `NeiryKitPlugin.companion`.

  **SinkDispatcher object** — define in the same file (or a separate `SinkDispatcher.kt` if preferred). This is a Kotlin-side dispatcher that the C callback calls via JNI reflection, eliminating the need to construct `Runnable` objects from C and avoiding local ref lifetime issues across `DetachCurrentThread`:
  ```kotlin
  object SinkDispatcher {
      @JvmStatic
      fun postSuccess(handler: Handler, sink: Any?, data: Any?) {
          handler.post { (sink as? EventChannel.EventSink)?.success(data) }
      }
      @JvmStatic
      fun postError(handler: Handler, sink: Any?, code: String, message: String, details: Any?) {
          handler.post {
              (sink as? EventChannel.EventSink)?.error(code, message, details)
              (sink as? EventChannel.EventSink)?.endOfStream()
          }
      }
      @JvmStatic
      fun postEndOfStream(handler: Handler, sink: Any?) {
          handler.post { (sink as? EventChannel.EventSink)?.endOfStream() }
      }
  }
  ```
  The `handler.post { }` lambda captures the Java-side references naturally — data objects are passed as JNI arguments (held on the JVM stack during the call), then captured by the Kotlin lambda inside `Handler.post`. No global refs for data needed, no Runnable construction from C, no ref lifecycle issues when the C thread detaches.

### Phase 2: JNI C layer

- [x] **Task 3: Rename nativeGetVersion JNI function** (depends on Task 2)
  Files: `android/src/main/cpp/jni_bridge.cpp`
  The existing `jni_bridge.cpp` declares `Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion`. Since Task 2 moves the `external fun nativeGetVersion()` declaration from `NeiryKitPlugin` to `NativeBridge`, the JNI function name must match. Rename:
  - From: `Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion`
  - To: `Java_com_neiry_neiry_1kit_NativeBridge_nativeGetVersion`
  The function body stays identical (`return env->NewStringUTF(clCCapsule_GetVersionString())`). Without this rename, calling `nativeBridge.nativeGetVersion()` at runtime throws `UnsatisfiedLinkError`.

- [x] **Task 4: jni_device_locator.cpp — full JNI implementation** (depends on Tasks 2, 3)
  Files: `android/src/main/cpp/jni_device_locator.cpp`
  Create the C++ file implementing all JNI functions declared in `NativeBridge` (except `nativeGetVersion` which stays in `jni_bridge.cpp`). Reference the iOS `DeviceLocatorBridge.swift` for behavioral parity. Key sections:

  **Global state:**
  - `static JavaVM* g_jvm` — initialized in `nativeCreateLocator` (first JNI call in lifecycle). Obtained via `env->GetJavaVM(&g_jvm)`.
  - `static jobject g_deviceListSink` — global ref to the Kotlin `EventSink` object. Guarded by `static pthread_mutex_t g_callback_mutex = PTHREAD_MUTEX_INITIALIZER`.
  - `static jobject g_handler` — global ref to `Handler(Looper.getMainLooper())`, created once in `nativeCreateLocator`.

  **Cached JNI IDs for SinkDispatcher** (resolved once, reused across callbacks):
  - `static jclass g_dispatcher_class` — global ref to `com/neiry/neiry_kit/SinkDispatcher`.
  - `static jmethodID g_postSuccess` — method ID for `SinkDispatcher.postSuccess(Handler, Object, Object)`.
  - `static jmethodID g_postError` — method ID for `SinkDispatcher.postError(Handler, Object, String, String, Object)`.
  - `static jmethodID g_postEndOfStream` — method ID for `SinkDispatcher.postEndOfStream(Handler, Object)`.
  Initialize all four in `nativeCreateLocator` right after obtaining `g_jvm`. Use `FindClass("com/neiry/neiry_kit/SinkDispatcher")` (literal path, NOT `neiry_1kit` — the `_1` encoding applies only to `Java_` function name prefixes, not class lookup strings). Convert the class ref to a global ref so it survives across threads.

  **Error encoding helper:**
  - `static void throw_sdk_error(JNIEnv* env, const clCError* error)` — reads `error->code` and `error->message` (char[256]), formats as `"<code>|<message>"` string, throws `java.lang.RuntimeException` with that string. Kotlin catches `RuntimeException` in the bridge class and calls `parseSdkError()` on it.

  **JNI function: `nativeCreateLocator(logDir)`:**
  - Stores `JavaVM*` via `env->GetJavaVM`.
  - Creates `Handler(Looper.getMainLooper())` as a global ref and stores in `g_handler`.
  - Resolves and caches `SinkDispatcher` class and method IDs (see above).
  - Calls `clCDeviceLocator_Create(&error)` or `clCDeviceLocator_CreateWithLogDirectory(dir, &error)`.
  - On error: `throw_sdk_error`.
  - Returns `(jlong)(uintptr_t)locator`.

  **JNI function: `nativeDestroyLocator(handle)`:**
  - Guard `handle == 0` → return.
  - Lock mutex, clear `g_deviceListSink` (delete global ref if non-null), unlock.
  - `clCDeviceLocator_Destroy((clCDeviceLocator)(uintptr_t)handle)`.

  **JNI function: `nativeSetDeviceListSink(sink)`:**
  - Lock mutex.
  - Delete old `g_deviceListSink` global ref if non-null.
  - If `sink != NULL`: `g_deviceListSink = env->NewGlobalRef(sink)`, else `g_deviceListSink = NULL`.
  - Unlock mutex.

  **JNI function: `nativeRequestDevices(handle, deviceType, searchTime)`:**
  - Register C callback via `clCDeviceLocator_SetOnDeviceListEvent(locator, on_device_list_callback)`.
  - Call `clCDeviceLocator_RequestDevices(locator, (clCDeviceType)deviceType, searchTime, &error)`.
  - On error: `throw_sdk_error`.

  **Static C callback `on_device_list_callback`:**
  - `AttachCurrentThread` to get `JNIEnv*`.
  - Lock mutex, copy `g_deviceListSink` to local `jobject sink_ref`. Copy `g_handler` to local. Unlock.
  - If `sink_ref == NULL` → `goto cleanup`.
  - Check `failReason`: if not OK, call `SinkDispatcher.postError(handler, sink, code, message, null)` via the cached `g_postError` method ID → `goto cleanup`.
  - Call `marshal_device_list(env, list)` to build a `java.util.ArrayList<HashMap<String, Object>>`.
  - Call `SinkDispatcher.postSuccess(handler, sink, arrayList)` via the cached `g_postSuccess` method ID.
  - Call `SinkDispatcher.postEndOfStream(handler, sink)` via the cached `g_postEndOfStream` method ID.
  - `cleanup:` label — `DetachCurrentThread` called on ALL return paths including early-return when sink is NULL.

  **Why SinkDispatcher solves the threading issue:** The C callback calls `SinkDispatcher.postSuccess(handler, sink, data)` as a regular JNI static method call. The `data` jobject (marshaled ArrayList) is a local ref passed as a JNI argument — it stays alive for the duration of the JNI call. Inside `SinkDispatcher.postSuccess`, Kotlin's `handler.post { sink.success(data) }` captures `data` as a Kotlin lambda variable (a strong Java reference). By the time `DetachCurrentThread` frees local refs, the lambda already holds its own reference. No global refs for data needed.

  **Helper `marshal_device_list(env, list)`:**
  - `clCDeviceInfoList_GetCount(list, &error)` — check error, return empty list on failure.
  - Loop: `clCDeviceInfoList_GetDeviceInfo(list, i, &error)` — skip entry on error.
  - For each entry: `clCDeviceInfo_GetSerial(info)`, `clCDeviceInfo_GetName(info)`, `clCDeviceInfo_GetType(info)` — note: `GetType` NOT `GetDeviceType`.
  - Build `HashMap` with keys `"serial"`, `"name"`, `"type"` (int).

  **JNI function: `nativeCreateDevice(locatorHandle, serial)`:**
  - Guard `locatorHandle == 0` → throw `RuntimeException("0|DeviceLocator not created")`.
  - `clCDeviceLocator_CreateDevice(locator, serial, &error)` — on error: `throw_sdk_error`.
  - Return `(jlong)(uintptr_t)device`.

  **JNI functions: `nativeSetSingleThreaded(enabled)`, `nativeUpdate(handle)`, `nativeSetLogLevel(level)`:**
  - Thin wrappers calling `clCCapsule_SetSingleThreaded(enabled)`, `clCDeviceLocator_Update(locator)`, `clCCapsule_SetLogLevel((clCCapsule_LogLevel)level)`.

- [x] **Task 5: Update CMakeLists.txt** (depends on Task 4)
  Files: `android/src/main/cpp/CMakeLists.txt`
  Add `jni_device_locator.cpp` to the `add_library` source list alongside `jni_bridge.cpp`.

### Phase 3: Kotlin bridge + plugin wiring

- [x] **Task 6: DeviceLocatorBridge.kt** (depends on Tasks 1, 2)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt`
  Create the Kotlin bridge class that owns the locator handle and implements `EventChannel.StreamHandler` for the `deviceList` EventChannel. Mirror the iOS `DeviceLocatorBridge.swift` behavior:

  **Class structure:**
  ```
  class DeviceLocatorBridge(
      private val nativeBridge: NativeBridge,
      private val mainHandler: Handler
  ) : EventChannel.StreamHandler
  ```
  - `private var handle: Long = 0L` — the native locator handle.
  - Companion object: `var devices: MutableMap<String, Long> = mutableMapOf()` — holds device handles created by `createDevice`, keyed by serial. `DeviceBridge` will look up entries here (same pattern as iOS `DeviceLocatorBridge.devices`).

  **Methods:**
  - `fun create(logDirectory: String?)` — calls `nativeBridge.nativeCreateLocator(logDirectory)`, stores returned handle. Wraps in try/catch: `catch (e: RuntimeException) { throw parseSdkError(e.message ?: "255|Unknown error") }`.
  - `fun createDevice(serial: String): Long` — guards `handle != 0L`, throws `FlutterError("NO_LOCATOR", "DeviceLocator not created", null)` if not. Calls `nativeBridge.nativeCreateDevice(handle, serial)`, stores result in `devices[serial]`, returns handle. Wraps JNI call in try/catch + `parseSdkError`.
  - `fun setSingleThreaded(enabled: Boolean)` — calls `nativeBridge.nativeSetSingleThreaded(enabled)`.
  - `fun update()` — guards `handle != 0L`, calls `nativeBridge.nativeUpdate(handle)`.
  - `fun setLogLevel(level: Int)` — calls `nativeBridge.nativeSetLogLevel(level)`.
  - `fun dispose()` — if `handle != 0L`: call `nativeBridge.nativeSetDeviceListSink(null)` to clear C-side callback ref, then `nativeBridge.nativeDestroyLocator(handle)`, set `handle = 0L`, clear `devices`.

  **StreamHandler (`onListen` / `onCancel`):**
  - `onListen(arguments, events)` — guards `handle != 0L`, calls `events?.error("NO_LOCATOR", ...)` and returns if not created. Extracts `deviceType: Int` and `searchTime: Int` from `arguments` map. Calls `nativeBridge.nativeSetDeviceListSink(events)` to pass the `EventSink` to the C callback. Then calls `nativeBridge.nativeRequestDevices(handle, deviceType, searchTime)`. On `RuntimeException`: parse via `parseSdkError`, call `events?.error(e.code, e.message, e.details)` then `events?.endOfStream()`, clear sink via `nativeSetDeviceListSink(null)`.
  - `onCancel(arguments)` — calls `nativeBridge.nativeSetDeviceListSink(null)` to clear the C-side callback ref.

- [x] **Task 7: Wire DeviceLocatorBridge into NeiryKitPlugin** (depends on Tasks 2, 6)
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Update the plugin to instantiate and use the bridge. Changes:

  - Remove `companion object { init { ... } }` block (library loading moved to `NativeBridge`).
  - Remove `private external fun nativeGetVersion(): String` declaration.
  - Add instance fields: `private var nativeBridge: NativeBridge? = null`, `private var deviceLocatorBridge: DeviceLocatorBridge? = null`.
  - In `onAttachedToEngine`: instantiate `NativeBridge()` (triggers library loading via its companion init), then `DeviceLocatorBridge(nativeBridge!!, Handler(Looper.getMainLooper()))`. Replace the `StubStreamHandler` for `neiry_kit/events/deviceList` with `deviceLocatorBridge` as the stream handler.
  - Rewrite `handleDeviceLocatorCall` to dispatch all supported methods with null-safe bridge access (`val bridge = deviceLocatorBridge ?: return result.error("NOT_INITIALIZED", "DeviceLocatorBridge not initialized", null)`):
    - `"getVersionString"` → `result.success(nativeBridge!!.nativeGetVersion())`.
    - `"create"` → extract optional `logDirectory` from args, call `bridge.create(logDirectory)`, `result.success(null)`.
    - `"createDevice"` → extract `serial` from args (guard `INVALID_ARGS` if missing), call `bridge.createDevice(serial)`, `result.success(null)`. (Handle storage is internal to `DeviceLocatorBridge.createDevice` — do not duplicate it here.)
    - `"setSingleThreaded"` → extract `enabled: Boolean`, call `bridge.setSingleThreaded(enabled)`, `result.success(null)`.
    - `"update"` → call `bridge.update()`, `result.success(null)`.
    - `"setLogLevel"` → extract `level: Int`, call `bridge.setLogLevel(level)`, `result.success(null)`.
    - `"dispose"` → call `bridge.dispose()`, `result.success(null)`.
    - All calls wrapped in `try { ... } catch (e: FlutterError) { result.error(e.code, e.message, e.details) } catch (e: Exception) { result.error("UNKNOWN", e.message, null) }`.
  - In `onDetachedFromEngine`: call `deviceLocatorBridge?.dispose()` before clearing channel handlers. Set `deviceLocatorBridge = null`, `nativeBridge = null`.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add shared Android infrastructure: NativeBridge, FlutterError, SinkDispatcher"
- **Commit 2** (after tasks 3-5): "Implement JNI device locator bridge with Kotlin-dispatched callbacks"
- **Commit 3** (after tasks 6-7): "Wire DeviceLocatorBridge into plugin with full method dispatch"
