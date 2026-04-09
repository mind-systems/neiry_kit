# Code Review: DeviceLocatorBridge (Android)

**Plan file:** `.ai-factory/plans/29-devicelocatorbridge.md`
**Reviewed:** 2026-04-09

**Files reviewed:** 7 (4 new, 3 modified)
**Risk Level:** 🟡 Medium

## Review Scope

| File | Status | Lines |
|---|---|---|
| `android/src/main/kotlin/com/neiry/neiry_kit/FlutterError.kt` | new | 27 |
| `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt` | new | 63 |
| `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt` | new | 113 |
| `android/src/main/cpp/jni_device_locator.cpp` | new | 302 |
| `android/src/main/cpp/jni_bridge.cpp` | modified | rename only |
| `android/src/main/cpp/CMakeLists.txt` | modified | +1 source file |
| `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt` | modified | full rewrite |

## Critical Issues

### 1. Dangling global ref in `on_device_list_callback` — use-after-free on concurrent dispose

`jni_device_locator.cpp:114-117` copies `g_deviceListSink` and `g_handler` as raw pointer values under the mutex, then uses them after the lock is released:

```c
pthread_mutex_lock(&g_callback_mutex);
jobject sink_ref    = g_deviceListSink;   // raw pointer copy
jobject handler_ref = g_handler;
pthread_mutex_unlock(&g_callback_mutex);

if (sink_ref) {
    // ... uses sink_ref and handler_ref as JNI arguments ...
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess,
        handler_ref, sink_ref, deviceArray);   // line 134
```

If `nativeSetDeviceListSink(null)` or `nativeDestroyLocator` runs on the main thread between the mutex unlock and the `CallStaticVoidMethod` call, `DeleteGlobalRef(g_deviceListSink)` invalidates the reference. `sink_ref` becomes a dangling pointer. ART's checked-JNI mode (enabled by default on debug builds) aborts the process when a deleted global ref is passed as a JNI argument:

```
JNI ERROR (app bug): accessed deleted global reference 0x...
```

This was flagged as a suggestion in plan-review-2. The timing window is narrow (callback fires once per scan), but the fix is one line per ref and makes the code correct:

```c
pthread_mutex_lock(&g_callback_mutex);
jobject sink_ref    = g_deviceListSink ? env->NewLocalRef(g_deviceListSink) : nullptr;
jobject handler_ref = g_handler        ? env->NewLocalRef(g_handler)        : nullptr;
pthread_mutex_unlock(&g_callback_mutex);

// ... use sink_ref and handler_ref ...

// After all SinkDispatcher calls:
if (sink_ref)    env->DeleteLocalRef(sink_ref);
if (handler_ref) env->DeleteLocalRef(handler_ref);
```

`NewLocalRef` creates an independent JNI reference that keeps the Java object alive regardless of whether the global ref is later deleted. Local refs are freed by `DetachCurrentThread`, but explicit cleanup is cleaner.

## Issues

### 2. `DeviceLocatorBridge.update()` behavioral parity with iOS

`DeviceLocatorBridge.kt:58-61`:
```kotlin
fun update() {
    if (handle == 0L) return   // silently returns
    nativeBridge.nativeUpdate(handle)
}
```

iOS throws `FlutterError("NO_LOCATOR", "DeviceLocator not created")` when `locator` is nil (`DeviceLocatorBridge.swift:85-88`). Android silently no-ops. Dart callers won't receive an error on Android when calling `update()` before `create()`.

Fix: throw the same error as iOS:
```kotlin
fun update() {
    if (handle == 0L) throw FlutterError("NO_LOCATOR", "DeviceLocator not created", null)
    nativeBridge.nativeUpdate(handle)
}
```

### 3. `mainHandler` constructor parameter is unused

`DeviceLocatorBridge.kt:14` accepts `mainHandler: Handler` but no method references it. All main-thread dispatch goes through the C-side `g_handler` via `SinkDispatcher`. The parameter is dead weight for this bridge.

If it's kept for constructor-shape consistency with future bridges, add a comment. Otherwise remove it, and update `NeiryKitPlugin.kt:23` which passes `Handler(Looper.getMainLooper())` — that Handler instance becomes garbage immediately.

## Suggestions

### 4. Success path: two separate `Handler.post` calls vs iOS single dispatch

`jni_device_locator.cpp:134-137`:
```c
env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess,
    handler_ref, sink_ref, deviceArray);
env->CallStaticVoidMethod(g_dispatcher_class, g_postEndOfStream,
    handler_ref, sink_ref);
```

Each call queues a separate Runnable on the main Looper. iOS batches both into a single `DispatchQueue.main.async { sink(data); sink(FlutterEndOfEventStream) }`. Android's Handler is FIFO, so the effect is identical in practice. But a single-dispatch approach would match iOS parity exactly. One option: add a `postSuccessAndEnd` method to `SinkDispatcher` that does both in one lambda.

Not a bug — just a tightening opportunity.

## Verified Correct

- **JNI function naming**: `Java_com_neiry_neiry_1kit_NativeBridge_*` in both `jni_bridge.cpp` and `jni_device_locator.cpp` — matches `NativeBridge` class with `_1` underscore encoding. `FindClass` paths correctly use literal `com/neiry/neiry_kit/` (no `_1`).
- **SinkDispatcher method signatures**: `postSuccess(Handler, Object, Object)V`, `postError(Handler, Object, String, String, Object)V`, `postEndOfStream(Handler, Object)V` — all match the Kotlin `@JvmStatic` declarations.
- **Error encoding**: `throw_sdk_error` formats `clCError` as `"%d|%s"`, `parseSdkError` splits on first `|`. Round-trips correctly for all SDK error codes including multi-digit codes.
- **Callback signature**: `on_device_list_callback(clCDeviceLocator, clCDeviceInfoList, clCDeviceLocator_FailReason)` matches the SDK typedef in `CDeviceLocator.h:101`.
- **Device info accessors**: `clCDeviceInfo_GetType` (not `GetDeviceType`) per `CDeviceInfo.h`. Null-guarded serial/name with `s ? s : ""`.
- **FailReason error codes**: `"1"` for `BluetoothDisabled`, `"255"` for `Unknown` — matches iOS parity (`DeviceLocatorBridge.swift:147,153`).
- **Thread safety**: mutex protects `g_deviceListSink` on all access paths. `GetEnv`/`AttachCurrentThread` pattern is correct — only detaches threads that the callback attached.
- **Local ref hygiene**: `marshal_device_list` deletes per-iteration refs (map, strings, boxed int) and shared refs (keys, classes) — no table overflow risk.
- **Dispose ordering**: `nativeSetDeviceListSink(null)` before `nativeDestroyLocator` prevents callbacks from firing after locator destruction.
- **NeiryKitPlugin catch ordering**: `catch (FlutterError)` before `catch (Exception)` — correctly captures the specific subclass first.
- **`result.error` returns inside try**: `return result.error("INVALID_ARGS", ...)` exits `handleDeviceLocatorCall` directly, bypassing the catch blocks. Correct — error was already sent to result.
- **onDetachedFromEngine**: bridge dispose runs before channel cleanup. The subsequent `setStreamHandler(null)` triggers `onCancel` → `nativeSetDeviceListSink(null)` which is a harmless redundant call on an already-null pointer.
- **NativeBridge instance-per-plugin**: regular class (not singleton), created in `onAttachedToEngine`, released in `onDetachedFromEngine`. Companion `init` for library loading runs once per classloader. No state leakage across hot restarts.

REVIEW_PASS
