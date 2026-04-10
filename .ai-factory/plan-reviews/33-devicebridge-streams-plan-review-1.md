# Plan Review: DeviceBridge — streams

**Plan file:** `.ai-factory/plans/33-devicebridge-streams.md`
**Files reviewed:** `jni_device.cpp`, `jni_device_locator.cpp`, `NativeBridge.kt`, `DeviceBridge.kt`, `NeiryKitPlugin.kt`, `DeviceBridge.swift` (iOS reference), `channel_names.dart`, `FlutterError.kt`, C SDK headers (`CDevice.h`, `CEEGTimedData.h`, `CPSDData.h`, `CEEGArtifacts.h`, `CResistances.h`)
**Risk Level:** 🔴 High

## Context Gates

- **ARCHITECTURE.md:** WARN — no violations. Plan follows the layered bridge architecture. All `external fun` on `NativeBridge` (centralized). Platform bridges don't cross-call.
- **RULES.md:** not present, skipped.
- **ROADMAP.md:** OK — plan maps to the `DeviceBridge — streams` milestone under Android bridges. Channel IDs, map keys, and behavior align with the iOS reference milestone that is already marked complete.

## Critical Issues

### 1. `static` linkage prevents extern — linker error

**Task 1** says to add `extern` declarations in `jni_device.cpp` for `g_jvm`, `g_handler`, `g_dispatcher_class`, and `g_postSuccess`, citing the existing `extern void throw_sdk_error(...)` precedent.

The precedent does not apply. `throw_sdk_error` is defined **without** `static` in `jni_device_locator.cpp` (line 23: `void throw_sdk_error(...)`) — it has external linkage. But all four globals are declared **with** `static` (lines 8-18):

```cpp
static JavaVM*   g_jvm              = nullptr;
static jobject   g_handler          = nullptr;
static jclass    g_dispatcher_class = nullptr;
static jmethodID g_postSuccess      = nullptr;
```

`static` at file scope gives them internal linkage. Adding `extern` declarations in `jni_device.cpp` will compile, but the linker will emit an **undefined symbol** error because the `static` definitions in `jni_device_locator.cpp` are invisible to other translation units.

**Fix:** Add `jni_device_locator.cpp` to Task 1's file list. Remove `static` from these 4 declarations so they have external linkage. Alternatively, move them to a shared header as `extern` declarations and define them (without `static`) in `jni_device_locator.cpp`.

### 2. Missing `nativeUnregisterDeviceCallbacks(old)` in `setDevice()`

**Task 2** modifies `DeviceBridge.kt.setDevice()` to call `nativeRegisterDeviceCallbacks(handle)` after storing the new handle, but does **not** call `nativeUnregisterDeviceCallbacks(old)` before releasing the old handle when `old != 0L && old != handle`.

The iOS reference (`DeviceBridge.swift`, line 113-116) explicitly calls `unregisterCallbacks()` before `clCDevice_Release(old)`:

```swift
if let old = device, old != handle {
    unregisterCallbacks()   // <-- clears all 8 SetOn*Event(dev, nil) + activeBridge = nil
    clCDevice_Release(old)
    channelNamesHandle = nil
}
```

Without this, the old device's 8 C callbacks remain registered pointing to the old `clCDevice` pointer. If the SDK fires a callback on the old device after `clCDevice_Release`, the `find_device_slot` will either find a stale slot (use-after-free risk) or miss it (silent data loss). Additionally, if the old slot is unregistered inside `nativeRegisterDeviceCallbacks` for the new device (which it isn't — `register_device_slot` fills a new slot), the old slot's sinks will leak their global refs.

**Fix:** In Task 2's `setDevice()` modification, add `nativeBridge.nativeUnregisterDeviceCallbacks(old)` before `nativeBridge.nativeReleaseDevice(old)` in the `old != 0L && old != handle` branch.

## Positive Notes

- **Thorough iOS parity.** All 8 map shapes (keys, types, nesting) match the iOS `DeviceBridge.swift` implementation exactly. The 19-key PSD map, individual alpha/beta soft-error sentinel pattern, and resistance no-`clCError*` accessor pattern are all correctly documented.
- **Correct C SDK callback signatures.** All 8 callback typedefs match `CDevice.h` — bare C function pointers with `(clCDevice, payload)` signature, no context parameter. The static device registry is the right solution for resolving which sinks to emit to.
- **Learned from past post-review fixes.** The plan correctly specifies `NewLocalRef` under mutex (not raw pointer copy) for all sink access in callbacks — avoiding the exact use-after-free that was fixed in the DeviceLocatorBridge post-review. `goto cleanup` with `DetachCurrentThread` on all paths is also correctly specified.
- **PSD individual alpha/beta error handling.** Correctly distinguishes hard bail (`HasIndividualAlpha` check fails → `goto cleanup`) from soft error (accessor fails → emit `-1` sentinel). Matches iOS behavior exactly.
- **Resistance accessor pattern.** Correctly notes that `clCResistance_GetCount`, `GetChannelName`, and `GetValue` take no `clCError*` parameter — verified against the C header.
