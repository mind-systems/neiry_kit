# Code Review: EmotionsBridge (Android)

**Plan:** `.ai-factory/plans/36-emotionsbridge.md`
**Review pass:** 1

## Files reviewed

| File | Status | Verdict |
|---|---|---|
| `android/src/main/cpp/jni_emotions.cpp` | New | OK |
| `android/src/main/cpp/CMakeLists.txt` | Modified | OK |
| `android/src/main/kotlin/com/neiry/neiry_kit/EmotionsBridge.kt` | New | OK |
| `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt` | Modified | OK |
| `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt` | Modified | OK |

## C API correctness (verified against `CEmotions.h`)

- `clCEmotions_Create(device, &error)` — takes `clCError*`. Code checks `error.success` and calls `throw_sdk_error` on failure. Correct.
- `clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, handler)` — NO `clCError*` param. Code calls directly without error check. Correct.
- `clCEmotions_SetOnErrorEvent(emotions, handler)` — NO `clCError*` param. Code calls directly without error check. Correct.
- Callback typedefs match forward declarations: `(clCEmotions, const clCEmotions_States*) NOEXCEPT` and `(clCEmotions, const char*) NOEXCEPT`. Correct.
- No `Destroy` function in the header — `nativeDisposeEmotions` only unregisters callbacks and clears sinks. Correct.

## Map shape (verified against iOS `EmotionsBridge.swift`)

State event map keys: `ts` (jlong), `attention` (jfloat), `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl` — matches iOS lines 60–67 exactly. All 5 float fields from `clCEmotions_States` covered, plus timestamp. Correct.

Error event map key: `message` (string, null-coalesced to `""`) — matches iOS line 73. Correct.

## JNI patterns (verified against `jni_nfb.cpp`)

- **Extern declarations:** Declares `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`, `throw_sdk_error`, `make_map`, `map_put_float`, `map_put_long`, `map_put_string`. No redefinitions. Only declares what is actually used (correctly omits `init_map_cache`, `map_put_int`, `map_put_object`, `map_put_double`, `map_put_bool`, `g_postError` — none needed here).
- **Sink management:** `NewGlobalRef`/`DeleteGlobalRef` under `pthread_mutex_t`, matching NfbBridge pattern.
- **Callback thread safety:** `NewLocalRef` snapshot of both sink and handler under lock (not raw pointer copy — per post-review fix #31). `goto cleanup` ensures `DeleteLocalRef` and `DetachCurrentThread` on all exit paths.
- **Dispose ordering:** Unregisters callbacks with `nullptr` before clearing sinks under mutex — prevents new callbacks from accessing freed refs. Matches `nativeDisposeNfb`.
- **JNI symbol encoding:** `Java_com_neiry_neiry_1kit_NativeBridge_native*` — `_1` for the underscore in `neiry_kit` package name. Correct.

## Kotlin layer (verified against `NfbBridge.kt`)

- `EmotionsBridge` class structure is identical to `NfbBridge`: constructor takes `NativeBridge`, inner `StreamHandler` class, two handler instances, `allStreamHandlers()`, `create()`/`dispose()`.
- `parseSdkError()` and `FlutterError` class confirmed to exist in `FlutterError.kt`.
- `DeviceBridge.requireHandle()` confirmed to exist.
- Channel IDs `"neiry_kit/events/emotionsState"` and `"neiry_kit/events/emotionsError"` match the already-registered entries in `NeiryKitPlugin.kt` event channel list (lines 83, 100).
- No calibrated factory path — correct, `CEmotions.h` exposes only one `Create` function.

## Plugin wiring (verified against `NeiryKitPlugin.kt`)

- Field declaration, instantiation, stream handler registration, `handleEmotionsCall`, and teardown all follow established patterns.
- Teardown order: `emotionsBridge` disposed before `nfbCalibratorBridge`, `nfbBridge`, `deviceLocatorBridge`, `deviceBridge` — classifiers before device, correct.
- `handleEmotionsCall` correctly obtains device handle from `devBridge.requireHandle()`, not from call arguments.

## Findings

No issues found.

REVIEW_PASS
