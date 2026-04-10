# Plan: DeviceLocatorBridge — post-review fixes

## Context

Fix two bugs in the Android DeviceLocatorBridge that passed code review incorrectly: a use-after-free race on JNI global refs in the device-list callback, and a missing `NO_LOCATOR` error in `update()` that breaks iOS parity.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: JNI callback ref safety

- [x] **Task 1: Replace raw pointer copy with `NewLocalRef` in `on_device_list_callback`**
  Files: `android/src/main/cpp/jni_device_locator.cpp`
  In `on_device_list_callback` (lines 114-117), the code snapshots `g_deviceListSink` and `g_handler` as raw `jobject` copies under the mutex. This is a use-after-free: if `nativeSetDeviceListSink(null)` runs concurrently on the Flutter thread and calls `DeleteGlobalRef(g_deviceListSink)`, the raw copy `sink_ref` becomes a dangling pointer — but the callback proceeds to pass it to `CallStaticVoidMethod`.

  Fix: while still holding the mutex, call `env->NewLocalRef(g_deviceListSink)` and `env->NewLocalRef(g_handler)` to create local JNI references that are independently ref-counted and survive a concurrent `DeleteGlobalRef` on the global. After the dispatch block (after line 139), delete the local refs with `env->DeleteLocalRef(sink_ref)` and `env->DeleteLocalRef(handler_ref)`. Also delete them on the early-return path when `sink_ref` is null to avoid leaking `handler_ref`.

  Specifically, replace lines 114-117:
  ```cpp
  pthread_mutex_lock(&g_callback_mutex);
  jobject sink_ref    = g_deviceListSink;
  jobject handler_ref = g_handler;
  pthread_mutex_unlock(&g_callback_mutex);
  ```
  with:
  ```cpp
  pthread_mutex_lock(&g_callback_mutex);
  jobject sink_ref    = g_deviceListSink ? env->NewLocalRef(g_deviceListSink) : nullptr;
  jobject handler_ref = g_handler        ? env->NewLocalRef(g_handler)        : nullptr;
  pthread_mutex_unlock(&g_callback_mutex);
  ```

  Then add cleanup before the `DetachCurrentThread` call. Restructure the tail of the function to always delete local refs:
  ```cpp
  // after the if (sink_ref) { ... } block:
  if (sink_ref)    env->DeleteLocalRef(sink_ref);
  if (handler_ref) env->DeleteLocalRef(handler_ref);

  if (attached) g_jvm->DetachCurrentThread();
  ```

### Phase 2: `update()` iOS parity

- [x] **Task 2: Throw `FlutterError("NO_LOCATOR")` in `DeviceLocatorBridge.update()` when `handle == 0L`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt`
  Currently `update()` (lines 58-61) silently returns when `handle == 0L`. The iOS `DeviceLocatorBridge.swift` `update()` (lines 85-90) throws `FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil)` when `locator` is nil. Android must match.

  Replace:
  ```kotlin
  fun update() {
      if (handle == 0L) return
      nativeBridge.nativeUpdate(handle)
  }
  ```
  with:
  ```kotlin
  fun update() {
      if (handle == 0L) {
          throw FlutterError("NO_LOCATOR", "DeviceLocator not created", null)
      }
      nativeBridge.nativeUpdate(handle)
  }
  ```

  The caller in `NeiryKitPlugin.kt` (line 130-133) dispatches `"update"` directly as `bridge.update()` with `result.success(null)`. Since `FlutterError` extends `Exception`, the existing `catch` pattern in the plugin will propagate it correctly to Dart as a `PlatformException`. Verify that the `"update"` dispatch in `NeiryKitPlugin.kt` is wrapped in a try-catch that handles `FlutterError` — if not, wrap it the same way other throwing calls like `createDevice` are wrapped (i.e. `catch (e: FlutterError) { result.error(e.code, e.message, e.details) }`).
