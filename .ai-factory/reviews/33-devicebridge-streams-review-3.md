# Code Review: DeviceBridge — streams (iteration 3)

**Plan:** `.ai-factory/plans/33-devicebridge-streams.md`
**Files reviewed:** `jni_device.cpp`, `jni_device_locator.cpp`, `NativeBridge.kt`, `DeviceBridge.kt`, `NeiryKitPlugin.kt`

## Summary

Both issues from review 2 are correctly addressed. No new critical issues found.

## Fixes Confirmed

### Issue 1 — `s_stringClass` before cache init: FIXED

`init_map_cache` is now called from `JNI_OnLoad`, which fires when the `.so` is first loaded — before any JNI function or SDK callback can execute. `s_stringClass` (and all other cached IDs) are guaranteed to be valid by the time any callback runs.

```cpp
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    init_map_cache(env);
    return JNI_VERSION_1_6;
}
```

`nativeRegisterDeviceCallbacks` no longer calls `init_map_cache` — correct, since `JNI_OnLoad` already guarantees it.

### Issue 2 — `nativeSetDeviceStreamSink` hardcoded to slot 0: FIXED

`MAX_DEVICES` is now `1`. With a single-element array, slot 0 is always the only slot, so the hardcoded index and `find_device_slot`/`register_device_slot` are now consistent by construction. The comment "plugin supports one device at a time" is now enforced structurally, not just by convention.

## Observations (non-blocking)

- **`on_eeg_data` `buf` / `sampleCount == 0` pattern** — still present, still not a live crash. The `if (sampleCount > 0)` guard on `SetFloatArrayRegion` is intact. Leaving as-is is fine.
- **Double `delete[] buf` in PSD** — still present, still correct. `delete[] nullptr` is a no-op; all paths are safe.
- **`JNI_OnLoad` only in `jni_device.cpp`** — verified there is no second definition in `jni_device_locator.cpp`. No linker conflict.
- **`static` removed correctly** — `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess` in `jni_device_locator.cpp` now have external linkage; all four `extern` declarations in `jni_device.cpp` resolve correctly.

## Verdict

**PASS.** All critical and blocking issues from prior reviews are resolved. Code is correct and ready.

REVIEW_PASS
