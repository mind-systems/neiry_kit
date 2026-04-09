# Plan Review: DeviceLocatorBridge (Android) — Round 2

**Plan file:** `.ai-factory/plans/29-devicelocatorbridge.md`
**Reviewed:** 2026-04-09

**Files Referenced:** 7 tasks across 7 target files
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge pattern. NativeBridge centralizes all `external fun` declarations, DeviceLocatorBridge owns the handle and StreamHandler. One bridge per C API module. Dependency rules respected (android/ depends on C SDK and Flutter engine only).
- **RULES.md:** WARN — file does not exist.
- **ROADMAP.md:** PASS — plan targets the next unchecked Android milestone ("DeviceLocatorBridge"). Scope matches: `jni_device_locator.cpp` + `DeviceLocatorBridge.kt`, NativeBridge, FlutterError, SinkDispatcher. All items described in the roadmap are covered.

## Previous Review Issues — All Resolved

All 5 findings from review-1 have been addressed:

1. **JNI rename for `nativeGetVersion`** — now explicit Task 3 with exact from/to function names.
2. **Runnable construction fragility** — replaced with SinkDispatcher pattern (Task 2), with a clear explanation of why it solves the threading issue.
3. **Local ref survival across `DetachCurrentThread`** — explained in the "Why SinkDispatcher solves the threading issue" section: data is captured by the Kotlin lambda before `DetachCurrentThread` frees local refs.
4. **Redundant handle storage wording** — Task 7 now says "(Handle storage is internal to `DeviceLocatorBridge.createDevice` — do not duplicate it here.)".
5. **`nativeSetDeviceListSink` parameter type** — Task 2 now uses `EventChannel.EventSink?` with a note that "the JNI side sees `jobject` regardless".

## Critical Issues

None.

## Suggestions

### 1. Use `NewLocalRef` when copying global refs under the mutex in `on_device_list_callback`

Task 4 says: "Lock mutex, copy `g_deviceListSink` to local `jobject sink_ref`. Copy `g_handler` to local. Unlock."

A raw pointer copy of a global ref is a dangling reference if `DeleteGlobalRef` is called concurrently — which happens when `nativeSetDeviceListSink(null)` runs on the main thread (via `onCancel`) while the callback fires on the background thread. ART aborts the process when a deleted global ref is used as a JNI argument.

Fix: under the lock, create JNI local refs instead of copying the pointer:

```c
pthread_mutex_lock(&g_callback_mutex);
jobject sink_local = (g_deviceListSink != NULL)
    ? env->NewLocalRef(g_deviceListSink) : NULL;
jobject handler_local = (g_handler != NULL)
    ? env->NewLocalRef(g_handler) : NULL;
pthread_mutex_unlock(&g_callback_mutex);
```

Local refs keep the Java objects alive independently of the global ref lifecycle. They are freed automatically by `DetachCurrentThread`, which runs after the SinkDispatcher calls.

The timing window is narrow (callback fires once per scan), but the fix is one line per ref and makes the pattern bulletproof.

### 2. Clean up `g_handler` and `g_dispatcher_class` on destroy/re-init

`nativeCreateLocator` creates `g_handler` and caches `g_dispatcher_class` + method IDs. `nativeDestroyLocator` only clears `g_deviceListSink`. If the Dart side calls `dispose()` then `create()` again (or on hot restart), `nativeCreateLocator` overwrites the old global refs without deleting them — leaking one `Handler` and one `Class` ref per cycle.

Fix: in `nativeCreateLocator`, before creating new global refs, check and delete existing ones. Alternatively, in `nativeDestroyLocator`, add cleanup for `g_handler` and `g_dispatcher_class`:

```c
// In nativeDestroyLocator, after clearing g_deviceListSink:
if (g_handler != NULL) {
    env->DeleteGlobalRef(g_handler);
    g_handler = NULL;
}
if (g_dispatcher_class != NULL) {
    env->DeleteGlobalRef(g_dispatcher_class);
    g_dispatcher_class = NULL;
}
// (method IDs become stale when class ref is deleted — re-resolve in next nativeCreateLocator)
```

### 3. `mainHandler` constructor parameter unused in DeviceLocatorBridge

Task 6 defines `DeviceLocatorBridge(nativeBridge, mainHandler)` but no bridge method uses `mainHandler` — all main-thread dispatch goes through JNI via `SinkDispatcher` + `g_handler`. The Kotlin-side Handler is dead weight for this bridge.

Options: drop it from the constructor (add it back when a future bridge actually needs it), or keep it for consistency if all bridges will share the same constructor shape. Either way is fine — just a note to avoid confusion during implementation.

## Positive Notes

- All 5 previous review findings are cleanly resolved. The SinkDispatcher pattern, Task 3 JNI rename, and explicit wording fixes show thoughtful iteration.
- The SinkDispatcher threading rationale is well-explained — the key insight (Kotlin lambda captures Java references before `DetachCurrentThread` frees local refs) is called out explicitly, which will prevent the implementer from second-guessing it.
- C API signatures verified against headers: `clCDeviceLocator_Create(&error)`, `clCDeviceInfoList_GetCount(list, &error)`, `clCDeviceInfo_GetType(info)` (not `GetDeviceType`), `clCDeviceLocator_DeviceListHandler(locator, list, failReason)` — all correct.
- `FindClass` path caveat (`neiry_kit` not `neiry_1kit`) correctly repeated in Task 4's cached JNI ID section.
- Error encoding (`"<code>|<message>"`) with first-`|`-split in `parseSdkError` preserves SDK error codes through the JNI boundary for Dart-side `NeiryErrorCode` mapping — matches iOS parity where `String(error.code.rawValue)` is used.
- Three commit boundaries (infra → JNI → Kotlin wiring) give clean bisect points if something breaks.

PLAN_REVIEW_PASS
