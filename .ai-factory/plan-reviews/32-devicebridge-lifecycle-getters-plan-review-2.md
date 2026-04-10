# Plan Review: DeviceBridge — lifecycle + getters (round 2)

**Files Reviewed:** 10 (plan + 9 codebase files)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** WARN — plan follows the layered bridge architecture correctly. One bridge class per C API module (`DeviceBridge.kt` wraps `clCDevice_*`). All `external fun` declarations on `NativeBridge` (centralized per established pattern). Platform channel dispatch in plugin. No dependency rule violations.
- **RULES.md:** WARN — file not present (no file).
- **ROADMAP.md:** WARN — the roadmap milestone "DeviceBridge — lifecycle + getters" lists all the methods this plan covers: `connect/disconnect/start/stop`, `getBatteryCharge`, `getMode` (no `clCError*`), sample rates, PPG amplitudes, and channel names with the two-step handle pattern. `getInfo` is deferred in the plan and also not listed in the Android roadmap line item. Full alignment.

## Review of First-Round Fixes

All five issues from plan-review-1 have been resolved:

1. **`throw_sdk_error` static linkage** — Plan now explicitly instructs removing `static` from `jni_device_locator.cpp` line 23 and adding `extern` declaration in `jni_device.cpp`. Verified against codebase: the function is indeed `static` at line 23. Fix is correct.

2. **Channel names handle caching** — Plan now adds `channelNamesHandle: Long = 0L` to `DeviceBridge.kt` (Task 6), implements `getOrCacheChannelNamesHandle()` mirroring iOS's pattern, and all channel name methods use `*FromHandle` JNI variants with the cached handle. Verified against `DeviceBridge.swift:89-404`: identical pattern.

3. **`getInfo` rationale** — Now correctly states "getInfo is a device-level API (`clCDevice_GetInfo` takes a `clCDevice` handle), not a locator-level call." Verified against `DeviceBridge.swift:441-453`.

4. **Disposal order** — Now matches iOS: `deviceLocatorBridge?.dispose()` first, then `deviceBridge?.release()`. Verified against `NeiryKitPlugin.swift:154-155`.

5. **No `"release"` case in `handleDeviceCall`** — Correctly removed with rationale: Dart has no `release` method, device handle release is plugin-level only. Matches iOS (no `"release"` case in `handleDeviceCall`).

## Critical Issues

None.

## Suggestions (non-blocking)

### 1. High-level channel name JNI functions are dead code

**File:** plan Task 3 + Task 5 + Task 6

Task 3 creates 8 JNI functions for channel names: 4 high-level (`nativeGetChannelNames`, `nativeGetChannelsCount`, `nativeGetChannelIndexByName`, `nativeGetChannelNameByIndex`) that acquire their own internal handle per call, and 4 `*FromHandle` variants that accept an externally cached handle. Task 5 declares all 8 as `external fun` in `NativeBridge.kt`. Task 6 only uses the `*FromHandle` variants via `getOrCacheChannelNamesHandle()`.

The 4 high-level functions are never called. They also leak the channel names handle on each invocation (since there is no release function and they don't cache). Not a bug since they're unreachable from Kotlin, but it's unnecessary code that could mislead future contributors.

**Suggestion:** Either remove the 4 high-level JNI functions + their `external fun` declarations, or add a comment marking them as unused convenience stubs.

### 2. `throw_sdk_error` sharing will need a header as JNI files grow

The plan uses an `extern` declaration at the top of `jni_device.cpp` to share `throw_sdk_error` from `jni_device_locator.cpp`. The roadmap lists 5 more JNI files (`jni_nfb.cpp`, `jni_emotions.cpp`, `jni_physio.cpp`, `jni_cardio.cpp`, `jni_productivity.cpp`), each of which will need the same `extern` declaration.

**Suggestion:** Consider extracting the declaration into a shared `jni_common.h` header in a future task. Not blocking for this plan — the `extern` approach works correctly.

## Verification Summary

| Plan assumption | Codebase reality | Match? |
|---|---|---|
| `throw_sdk_error` is `static` at line 23 | `static void throw_sdk_error(...)` at line 23 | ✅ |
| `CMakeLists.txt` has `jni_bridge.cpp` + `jni_device_locator.cpp` | Lines 8-9 confirm both sources | ✅ |
| `NativeBridge.kt` centralizes `external fun` | Lines 13-36, all device locator natives are here | ✅ |
| `DeviceLocatorBridge.devices` is companion object `MutableMap` | Lines 19-21 confirm `companion object { var devices: MutableMap<String, Long> }` | ✅ |
| `handleDeviceCall` is a stub returning `notImplemented()` | Line 156-158 confirm stub | ✅ |
| `FlutterError` + `parseSdkError()` exist and are reusable | `FlutterError.kt` lines 1-27 confirm both | ✅ |
| iOS `setDevice` releases old handle, resets `channelNamesHandle` | `DeviceBridge.swift:111-119` confirms | ✅ |
| iOS `getMode()` has no error param, returns -1 for nil device | `DeviceBridge.swift:463-466` confirms | ✅ |
| iOS disposal: locator dispose → device release | `NeiryKitPlugin.swift:154-155` confirms | ✅ |
| `createDevice` is on `device_locator` channel, not `device` | `NeiryKitPlugin.swift:104` and `.kt:116` confirm | ✅ |
| iOS channel names use cached handle via `getOrCacheChannelNamesHandle()` | `DeviceBridge.swift:391-404` confirms | ✅ |
| JNI function name prefix is `Java_com_neiry_neiry_1kit_NativeBridge_` | Existing functions in `jni_device_locator.cpp` use this prefix | ✅ |
| `onDetachedFromEngine` currently has no `deviceBridge` cleanup | Lines 188-202 confirm — only locator + channels cleaned | ✅ |

## Positive Notes

- Thorough iOS parity: every method, error path, and edge case (getMode no-throw, channel names caching, disposal order) cross-referenced against the Swift implementation.
- Correct JNI handle casting pattern `(clCDevice)(uintptr_t)handle` matches established code in `jni_device_locator.cpp`.
- The plan correctly identifies that `connect` must extract `bipolarChannels` from args (default `false`), matching both the iOS bridge and the Dart API.
- Clean separation of concerns: `DeviceBridge.kt` owns the device handle, while `DeviceLocatorBridge.devices` is a transient holding map cleared after handoff.
- `channelNamesHandle` is reset to `0L` on device change in `setDevice` — prevents stale cache from returning channel names for a different device.
- Error propagation chain (`throw_sdk_error` → `RuntimeException` → `parseSdkError()` → `FlutterError` → `result.error()`) is consistent with the established DeviceLocatorBridge pattern.
- Two-commit plan (JNI layer → Kotlin + wiring) follows build dependency order and keeps commits reviewable.

PLAN_REVIEW_PASS
