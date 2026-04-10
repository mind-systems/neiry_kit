# Code Review: DeviceLocatorBridge — post-review fixes

**Files reviewed:** `jni_device_locator.cpp`, `DeviceLocatorBridge.kt`
**Supporting context:** `NeiryKitPlugin.kt`, `FlutterError.kt`, `DeviceLocatorBridge.swift` (iOS parity reference)

## Change 1: `NewLocalRef` in `on_device_list_callback`

**Correctness: OK.**

The fix replaces raw `jobject` copies with `NewLocalRef` under the mutex, creating independently ref-counted local references that survive a concurrent `DeleteGlobalRef` on the Flutter thread (in `nativeSetDeviceListSink(null)` or `nativeDestroyLocator`). This is the textbook JNI solution for this race.

Verified:
- `NewLocalRef` calls are inside the mutex — no window where the global ref is freed before the local ref is created.
- Ternary null checks (`g_deviceListSink ? env->NewLocalRef(...) : nullptr`) are correct and clearer than relying on `NewLocalRef(nullptr)` returning null.
- `DeleteLocalRef` on lines 142-143 correctly covers all code paths: both-non-null (dispatch happened), sink-null-handler-non-null (dispatch skipped), and both-null (both skipped). Null checks prevent `DeleteLocalRef(nullptr)`.
- When `attached == true`, `DetachCurrentThread` would auto-free local refs anyway, but the explicit `DeleteLocalRef` is necessary for the `attached == false` case (callback on an already-attached thread, e.g. single-threaded mode) where no automatic cleanup frame exists.
- `g_dispatcher_class` is used directly in the callback without `NewLocalRef` — this is fine because it is a permanent global ref (created once in `nativeCreateLocator`, never deleted).

## Change 2: `FlutterError` throw in `update()`

**Correctness: OK.**

`DeviceLocatorBridge.update()` now throws `FlutterError("NO_LOCATOR", "DeviceLocator not created", null)` when `handle == 0L`, matching iOS `DeviceLocatorBridge.swift` lines 85-90.

Error propagation verified: `NeiryKitPlugin.handleDeviceLocatorCall` wraps the entire `when` block (lines 106-153) in `try { ... } catch (e: FlutterError) { result.error(e.code, e.message, e.details) }`. The `"update"` case at line 130 is inside this try block. The thrown `FlutterError` (which extends `Exception`) is caught and forwarded to Dart as `PlatformException`. No propagation gap.

The JNI `nativeUpdate` function (line 293) retains its own `if (handle == 0) return` guard — this is harmless since Kotlin throws before reaching JNI. The redundant guard is defensive and fine to keep.

## No issues found

Both changes are correct, minimal, and match the plan.

REVIEW_PASS
