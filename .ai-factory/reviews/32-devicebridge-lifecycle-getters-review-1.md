# Code Review: DeviceBridge — lifecycle + getters

**Files Reviewed:** 6 changed files + iOS counterparts for cross-reference
**Risk Level:** 🟢 Low

## Plan Review Issues — Verification

All 5 issues from the plan review have been addressed:

1. **`throw_sdk_error` static removal** — ✅ `static` removed at `jni_device_locator.cpp:23`, `extern` declared at `jni_device.cpp:7`.
2. **Channel names handle caching** — ✅ `channelNamesHandle` field + `getOrCacheChannelNamesHandle()` in `DeviceBridge.kt:58-68`. Reset on device change (`setDevice:51`) and release (`release:119`).
3. **`getInfo` rationale corrected** — ✅ `NeiryKitPlugin.kt:182` just calls `result.notImplemented()` with no misleading comment.
4. **Disposal order matches iOS** — ✅ `NeiryKitPlugin.kt:240-241`: locator dispose → device release, matching `NeiryKitPlugin.swift:154-155`.
5. **`"release"` dead code removed** — ✅ Not present in `handleDeviceCall`.

## Issues

### 1. Missing null guard on channel names handle — native crash risk

**File:** `jni_device.cpp:273-285` (`nativeGetRawChannelNamesHandle`)

If `clCDevice_GetChannelNames` returns NULL with `error.success == true`, the JNI function returns 0. The Kotlin `getOrCacheChannelNamesHandle()` stores 0 in `channelNamesHandle`, then callers pass 0 to `*FromHandle` JNI functions (e.g. `nativeGetChannelsCountFromHandle`), which cast it to a null C pointer and call SDK functions on it — likely a SIGSEGV (native crash, kills the app).

iOS guards against this explicitly (`DeviceBridge.swift:399-401`):
```swift
guard let handle = handle else {
    throw FlutterError(code: "NULL_HANDLE",
                       message: "clCDevice_GetChannelNames returned nil", details: nil)
}
```

**Fix:** Add a null check in `nativeGetRawChannelNamesHandle` after the success check:

```c
if (names == nullptr) {
    jclass cls = env->FindClass("java/lang/RuntimeException");
    if (cls) env->ThrowNew(cls, "0|clCDevice_GetChannelNames returned null");
    return 0;
}
```

Or alternatively, guard in the Kotlin `getOrCacheChannelNamesHandle()`:

```kotlin
val namesHandle = nativeBridge.nativeGetRawChannelNamesHandle(h)
if (namesHandle == 0L) {
    throw FlutterError("NULL_HANDLE", "clCDevice_GetChannelNames returned null", null)
}
```

### 2. High-level channel name JNI functions are dead code that leaks handles if called

**Files:** `jni_device.cpp:170-271`, `NativeBridge.kt:51-54`

Four JNI functions (`nativeGetChannelNames`, `nativeGetChannelsCount`, `nativeGetChannelIndexByName`, `nativeGetChannelNameByIndex`) and their Kotlin declarations are never called. `DeviceBridge.kt` exclusively uses the `*FromHandle` variants via the cached handle path.

Each high-level function internally calls `clCDevice_GetChannelNames()` to get a fresh names handle, uses it, then discards it. Since there is no release function for channel names handles, every call would leak a handle — the exact problem the plan review identified and the `*FromHandle` + caching approach was designed to solve.

These functions are safe as dead code, but they are a footgun: any future developer could call them directly from `NativeBridge` (which is a public class) and silently leak handles.

**Fix:** Remove the 4 high-level functions from both `jni_device.cpp` and `NativeBridge.kt`, or add a comment on each Kotlin declaration warning about the leak. Removing is cleaner.

## Positive Notes

- Error propagation chain is correct: JNI `throw_sdk_error` → `RuntimeException` → `parseSdkError()` → `FlutterError` → `result.error()`.
- Channel names caching in `DeviceBridge.kt` mirrors iOS's `getOrCacheChannelNamesHandle()` exactly, including reset on device change.
- `getMode()` correctly has no guard/throw and returns -1 for missing handle, matching iOS.
- `setDevice` correctly releases old handle if it differs and resets cached channel names handle.
- JNI naming conventions (`Java_com_neiry_neiry_1kit_NativeBridge_*`) are consistent with existing `jni_device_locator.cpp`.
- CMakeLists.txt registration is correct.
- `handleDeviceCall` error handling (`try/catch FlutterError + Exception`) matches `handleDeviceLocatorCall` exactly.
- `createDevice` flow in `NeiryKitPlugin.kt:118-128` correctly transfers handle from locator's devices map to device bridge, matching iOS lines 112-114.

REVIEW_PASS
