# Plan Review: DeviceBridge — lifecycle + getters

**Files Reviewed:** 10 (plan + 9 codebase files)
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** WARN — plan follows the layered bridge architecture (one bridge class per C API module, `external fun` on `NativeBridge`, platform channel dispatch in plugin). No boundary violations.
- **RULES.md:** not present (no file).
- **ROADMAP.md:** WARN — roadmap milestone lists `getBatteryCharge`, `getMode`, sample rates, PPG amplitudes, and channel names. Plan covers all of these. `getInfo` is listed in iOS bridge but not in the Android roadmap line item, so the omission is consistent with the roadmap. However, the plan's stated rationale for skipping `getInfo` is wrong (see issue #3 below).

## Critical Issues

### 1. `throw_sdk_error` is `static` — extern declaration will cause linker error

**File:** `android/src/main/cpp/jni_device_locator.cpp:23`, plan Task 1

The plan says to reuse `throw_sdk_error` by adding `extern void throw_sdk_error(JNIEnv* env, const clCError* error);` at the top of `jni_device.cpp`. However, `throw_sdk_error` is declared `static` in `jni_device_locator.cpp`:

```c
static void throw_sdk_error(JNIEnv* env, const clCError* error) {
```

`static` gives the function internal linkage — it is invisible to other translation units. The `extern` declaration in `jni_device.cpp` will compile but fail at link time with "undefined reference to `throw_sdk_error`".

**Fix options (pick one):**
1. Remove `static` from the definition in `jni_device_locator.cpp` AND use `extern` in `jni_device.cpp` (minimal change, plan's intent)
2. Extract to a shared header (`jni_common.h`) + shared source file
3. Duplicate the function in `jni_device.cpp` (most isolated but violates DRY)

Option 1 is the most aligned with the plan's stated preference for minimizing changes. The plan must explicitly note that `static` needs to be removed.

### 2. Channel names handle not cached — potential handle leak

**File:** plan Task 3 + Task 6, compare with `ios/Classes/DeviceBridge.swift:89-91`

iOS caches the `clCDevice_ChannelNames` handle in `getOrCacheChannelNamesHandle()` with this comment:

> Cached `clCDevice_ChannelNames` handle. There is no release function for this type, so we cache it to avoid leaking handles on repeated calls.

The plan explicitly skips caching at both JNI and Kotlin levels: "Each function gets its own names handle (no caching at JNI level — caching happens in Kotlin's DeviceBridge.kt if needed later)." But Kotlin's `DeviceBridge.kt` (Task 6) doesn't implement caching either.

If `clCDevice_GetChannelNames` allocates a new opaque handle on each call and there is no release function, every call leaks. iOS solved this by caching. The Android plan should cache at the Kotlin level (add a `channelNamesHandle: Long = 0L` field to `DeviceBridge.kt`, call `nativeGetChannelNames` once and store) or at the JNI level.

## Issues

### 3. `getInfo` skip rationale is factually wrong

**File:** plan Task 7, `"getInfo"` case

The plan says: "delegate to locator bridge (not device bridge) — skip for now, mark `result.notImplemented()` (getInfo uses locator-level DeviceInfo, not device-level)."

This is incorrect. iOS's `DeviceBridge.swift:441-453` calls `clCDevice_GetInfo(dev, &error)` — a device-level API. The C header confirms `clCDevice_GetInfo` takes a `clCDevice` handle, not a locator. The scoping decision to defer `getInfo` is valid (the roadmap line item doesn't explicitly list it), but the stated rationale is wrong and could mislead the implementer into wiring it to the locator bridge later.

**Fix:** Change the comment to "getInfo deferred to a separate task" or implement it now (requires adding `nativeGetInfo` to JNI + NativeBridge + DeviceBridge).

### 4. Disposal order differs from iOS

**File:** plan Task 7 point 4

The plan says: "In `onDetachedFromEngine`, add `deviceBridge?.release()` before `deviceLocatorBridge?.dispose()`."

iOS does the opposite — `deviceBridge?.release()` is called **after** `bridge.dispose()` (locator) in `NeiryKitPlugin.swift:155`. While the order likely doesn't matter functionally (device handles are independent once created), the divergence from iOS is unexplained. For consistency, release after locator dispose, matching iOS.

### 5. `"release"` method dispatch is dead code

**File:** plan Task 7, `handleDeviceCall` → `"release"` case

The Dart `DeviceMethods` class (`lib/src/channel/channel_names.dart:84-103`) has no `release` method name. The Dart `Device.dispose()` calls `DeviceMethods.disconnect`, not `release`. iOS's `handleDeviceCall` has no `"release"` case either — device release is triggered at the plugin level during locator disposal. This case would never be reached.

**Fix:** Remove the `"release"` case from `handleDeviceCall`. Device release should happen in `onDetachedFromEngine` (as the plan already describes) and in the locator's `"dispose"` handler (matching iOS lines 148-155).

## Positive Notes

- Correct identification that `clCDevice_GetMode` takes no `clCError*` — handled with no-throw, return -1 for null handle, matching iOS exactly.
- JNI naming convention (`Java_com_neiry_neiry_1kit_NativeBridge_<name>`) is consistent with the existing `jni_device_locator.cpp`.
- Error propagation chain (`throw_sdk_error` → `RuntimeException` → `parseSdkError()` → `FlutterError`) correctly follows the established pattern from DeviceLocatorBridge.
- Task decomposition (JNI first → Kotlin → wiring) is logical and matches the build dependency order.
- Correct note about `FindClass` paths using literal `neiry_kit` (not `_1` encoded).
- The two-step channel names handle pattern matches the C SDK API exactly.
- Commit plan is clean: JNI layer in one commit, Kotlin layer in another.
