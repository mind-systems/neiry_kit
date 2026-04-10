## Plan Review: NfbBridge (Android)

**Plan file:** `.ai-factory/plans/34-nfbbridge.md`
**Files reviewed:** 12 (plan + 11 codebase files)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — Plan places `NfbBridge.kt` directly in the `com.neiry.neiry_kit` package, but `ARCHITECTURE.md` specifies a `classifiers/` subdirectory (`android/src/main/kotlin/.../classifiers/NfbBridge.kt`). The existing Kotlin bridges (`DeviceBridge.kt`, `DeviceLocatorBridge.kt`) are in the flat package, so the plan follows the established Android convention. Not blocking, but worth noting the divergence from the target layout.
- **RULES.md:** File does not exist. WARN (non-blocking).
- **ROADMAP.md:** Plan implements the `NfbBridge` item under "Android bridges", which is the next unchecked milestone. Aligned. ✅

### Critical Issues

None.

### Issues

**1. Confusing description of null-calibrator error throw (Task 4)**

Task 4 says: *"call `throw_sdk_error` with an encoded string `"0|clCNFBCalibrator_CreateOrGet returned null"`"* — but `throw_sdk_error` takes a `const clCError*`, not a string. The parenthetical "(using `ThrowNew` with `RuntimeException`)" clarifies the intent, but the sentence reads as if `throw_sdk_error` is being called. An implementer needs to use `env->ThrowNew(RuntimeException, "0|...")` directly, not `throw_sdk_error`.

Recommend: reword to *"Throw a `RuntimeException` via `ThrowNew` with the encoded message `"0|clCNFBCalibrator_CreateOrGet returned null"`"* — dropping the `throw_sdk_error` reference entirely.

**2. Unnecessary `init_map_cache` extern (Task 2)**

Task 2 includes `init_map_cache` in the extern declarations for `jni_nfb.cpp`. This function is only called from `JNI_OnLoad` (in `jni_device.cpp`, line 199) during library load and is never needed by `jni_nfb.cpp`. The extern is harmless but unnecessary — could confuse an implementer into thinking it needs to be called.

Recommend: remove `init_map_cache` from the extern list in Task 2.

**3. No shared header for common JNI externs — technical debt for future bridges**

The plan has `jni_nfb.cpp` declare `extern` for `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`, `throw_sdk_error`, `make_map`, `map_put_float`, `map_put_long`, `map_put_string`. The ROADMAP shows 5 more bridges coming (NfbCalibrator, Emotions, Physio, Cardio, Productivity) — each will duplicate this same extern block.

A `jni_common.h` header with these declarations would eliminate the duplication. This plan established the pattern (the Emotions bridge roadmap item already says "declare them as `extern`... do NOT redefine"), so the debt starts here.

Not blocking this plan — but worth a follow-up task to extract a shared header before implementing the remaining bridges.

### Verification Against Codebase

**Task 1 — static removal:** Verified. All 14 cache variables (lines 72–85 of `jni_device.cpp`) and 9 functions (`init_map_cache`, `make_map`, `map_put_int/long/float/double/string/bool/object`, lines 87–177) are currently `static`. Device-private symbols (`DeviceSlot`, `g_device_slots`, `g_device_mutex`, slot helpers, callbacks) correctly remain `static`. ✅

**Task 2 — extern declarations:** Verified. `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess` are non-static in `jni_device_locator.cpp`. `throw_sdk_error` is non-static with `extern` already declared in `jni_device.cpp` (line 9). ✅

**Tasks 3–4 — JNI create functions:** Verified cast pattern `(clCDevice)(uintptr_t)handle` matches `jni_device.cpp` line 209. `clCNFB_Create` and `clCNFB_CreateCalibrated` signatures match iOS usage in `NfbBridge.swift` lines 38 and 71. `clCNFBCalibrator_CreateOrGet` null check matches iOS line 47. `clCIndividualNFBData` 10-field population matches iOS lines 51–65. ✅

**Tasks 5–6 — sink management and dispose:** Verified. Mutex + global ref pattern matches `nativeSetDeviceStreamSink` in `jni_device.cpp`. No `clCNFB_Destroy` confirmed by iOS `NfbBridge.swift` line 77 comment. ✅

**Task 7 — on_nfb_state_changed callback:** Verified map keys match iOS exactly: `"ts"` (Int64/long), `"delta"`, `"theta"`, `"alpha"`, `"smr"`, `"beta"` (all Float). See `NfbBridge.swift` lines 93–100. `goto cleanup` + `NewLocalRef` under mutex pattern matches `jni_device.cpp` device callbacks. ✅

**Task 8 — on_nfb_error callback:** Verified map key `"message"` matches iOS `NfbBridge.swift` line 107. ✅

**Task 9 — CMakeLists.txt:** Verified current source list is `jni_bridge.cpp`, `jni_device_locator.cpp`, `jni_device.cpp` (lines 7–11). Adding `jni_nfb.cpp` is correct. ✅

**Task 10 — NativeBridge.kt externals:** Verified all existing externals are on `NativeBridge` class (lines 24–62). New NFB externals follow the same pattern. ✅

**Task 11 — NfbBridge.kt:** Verified `DeviceBridge.DeviceStreamHandler` inner class pattern (lines 45–54) and `allStreamHandlers()` return type (line 66). `NfbBridge.kt` correctly mirrors this. EventChannel IDs `"neiry_kit/events/nfbState"` and `"neiry_kit/events/nfbError"` match `channel_names.dart` lines 35 and 63. ✅

**Task 12 — Plugin wiring:** Verified:
- `handleNfbCall` is currently a stub returning `notImplemented()` (line 216–218). ✅
- iOS `handleNfbCall` (line 314–348) uses `deviceBridge.requireDevice()` — Android equivalent is `DeviceBridge.requireHandle()` which is currently **private** (line 83). Making it public is explicitly addressed. ✅
- iOS teardown order (lines 148–155): classifiers → locator → device. Plan matches. ✅
- `streamHandlerMap` builder (lines 49–54) needs NFB handlers added. Plan uses `nfbBridge!!.allStreamHandlers()` — matches the `deviceBridge!!.allStreamHandlers()` pattern on line 51. ✅

### Positive Notes

- The plan is exceptionally well-structured — each task has explicit dependencies, exact file paths, and references to the iOS counterpart.
- Threading safety is thoroughly addressed: `pthread_mutex_t` for sink globals, `NewLocalRef` under lock, `goto cleanup` for `DetachCurrentThread` — all patterns that were learned from the DeviceLocatorBridge post-review fixes.
- The flat JNI parameter approach for `nativeCreateNfbCalibrated` (Task 4) is a smart decision — avoids complex JNI `HashMap` parsing for 10 typed fields, delegating the map-to-args conversion to Kotlin where it's trivial.
- Commit plan groups tasks logically: skeleton → JNI functions → wiring.

PLAN_REVIEW_PASS
