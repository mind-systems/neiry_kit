# Plan Review: EmotionsBridge (Android)

**Plan file:** `.ai-factory/plans/36-emotionsbridge.md`
**Reviewer pass:** 1

## Review Summary

**Files Reviewed:** 12 (plan + all referenced source files)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — Architecture shows classifiers in `android/src/main/kotlin/.../classifiers/` subdirectory, but actual codebase keeps all bridge files flat in `com/neiry/neiry_kit/`. Plan correctly follows the actual codebase layout, not the aspirational structure. No action needed.
- **RULES.md:** File does not exist. WARN — non-blocking.
- **ROADMAP.md:** Plan aligns with the `EmotionsBridge` milestone (Android bridges section, currently unchecked). Milestone description matches plan scope exactly: `jni_emotions.cpp` + `EmotionsBridge.kt`, no Destroy, no `clCError*` on SetOn*Event, extern map helpers from `jni_device.cpp`.

### Critical Issues

None.

### Verification Details

**Task 1 — `jni_emotions.cpp`:**

- **C API usage verified against `CEmotions.h`:** `clCEmotions_Create(device, &error)` takes `clCError*` — plan correctly checks `error.success`. `clCEmotions_SetOnEmotionalStatesUpdateEvent` and `clCEmotions_SetOnErrorEvent` take NO `clCError*` — plan correctly skips error checks. Callback typedefs match plan's forward declarations exactly.
- **Map shape matches iOS:** Plan's 6-key state map (`ts`, `attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl`) is identical to `EmotionsBridge.swift` lines 60–67. Error map shape (`message` key, null-coalesced to `""`) matches iOS line 73.
- **Extern declarations are correct and sufficient:** `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess` from `jni_device_locator.cpp`; `make_map`, `map_put_float`, `map_put_long`, `map_put_string` from `jni_device.cpp`; `throw_sdk_error` from `jni_device_locator.cpp`. All are used by the planned code. Note: `jni_nfb.cpp` also declares `init_map_cache` as extern but never calls it — the plan omits this unused declaration, which is cleaner.
- **Thread safety pattern matches `jni_nfb.cpp`:** Mutex-guarded `NewLocalRef` snapshot of sinks (not raw pointer copy — learned from post-review fix #31), `goto cleanup`, `DetachCurrentThread` on all paths.
- **`nativeDisposeEmotions` pattern matches `nativeDisposeNfb`:** Unregister callbacks with `nullptr`, then mutex-guarded `DeleteGlobalRef` of both sinks.

**Task 2 — CMakeLists.txt:**

- Placement after `jni_nfb_calibrator.cpp` is correct. No other build changes needed — no new libraries, no new include paths.

**Task 3 — `NativeBridge.kt`:**

- Four `external fun` declarations are consistent with the NFB pattern. Signature types (`Long`, `EventChannel.EventSink?`) match JNI function signatures.

**Task 4 — `EmotionsBridge.kt`:**

- Class structure mirrors `NfbBridge.kt` exactly: constructor takes `NativeBridge`, inner `StreamHandler` class, two handler instances, `allStreamHandlers()` returning pairs, `create()/dispose()` with handle guard, `parseSdkError()` on `RuntimeException`.
- Channel IDs (`neiry_kit/events/emotionsState`, `neiry_kit/events/emotionsError`) match both the iOS bridge and the already-registered stub entries in `NeiryKitPlugin.kt` lines 80 and 97.
- Correctly omits calibrated factory path — `clCEmotions` has only one `Create` function.

**Task 5 — Plugin wiring (`NeiryKitPlugin.kt`):**

- **Field declaration:** Matches existing bridge field pattern.
- **`onAttachedToEngine`:** Instantiation after `nfbCalibratorBridge` is correct. Stream handler registration in `buildMap` block follows the exact same `for ((id, handler) in bridge.allStreamHandlers())` pattern used for NFB/NFBCalibrator.
- **`handleEmotionsCall` implementation:** Replacing `result.notImplemented()` stub. The proposed `when` block with `create`/`dispose` branches mirrors `handleNfbCall` (lines 226–256) and iOS `handleEmotionsCall`. Correctly obtains device handle from `devBridge.requireHandle()` (not from call arguments). Error handling with `FlutterError`/`Exception` catch matches all other handlers.
- **`onDetachedFromEngine` teardown:** Adding `emotionsBridge?.dispose()` before `deviceLocatorBridge?.dispose()` maintains the correct teardown order (classifiers → device → locator), consistent with iOS teardown at lines 148–155 of `NeiryKitPlugin.swift`.

### Positive Notes

- Plan is exceptionally well-structured — each task lists exact file paths, function signatures, and behavioral constraints.
- The "no `clCError*` on `SetOn*Event`" constraint is prominently called out, preventing the most common error pattern in this codebase.
- Correct identification that Emotions needs no calibrated factory path, no Destroy, and only two event channels — keeping the implementation minimal.
- The `NewLocalRef` pattern under mutex lock is correctly specified, avoiding the use-after-free issue that was caught in post-review fix #31.
- Map key names are explicitly listed and verified against both the C struct and the iOS implementation — no room for typo-induced data mismatches.

PLAN_REVIEW_PASS
