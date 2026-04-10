## Code Review: NfbBridge (Android)

**Plan:** `.ai-factory/plans/34-nfbbridge.md`
**Files reviewed:** 7 changed files (2 new, 5 modified)

### File-by-file analysis

#### `jni_nfb.cpp` (new, 243 lines)

**Correctness:** All JNI functions, callbacks, and threading patterns are correct and match the established patterns in `jni_device.cpp` / `jni_device_locator.cpp`.

- `nativeCreateNfb` — casts, error handling, callback registration all correct. ✅
- `nativeCreateNfbCalibrated` — null-check on `clCNFBCalibrator_CreateOrGet` uses `ThrowNew` with RuntimeException (not `throw_sdk_error`), matching the roadmap spec. All 10 `clCIndividualNFBData` fields populated. `failReason` cast to `clCIndividualNFBCalibrationFailReason` (no underscore after `clC`). ✅
- `nativeSetNfbStateSink` / `nativeSetNfbErrorSink` — two separate functions (not one with streamType dispatch), mutex-guarded global ref swap. Pattern matches `nativeSetDeviceStreamSink` exactly. ✅
- `nativeDisposeNfb` — unregisters callbacks before mutex-guarded sink cleanup. No `clCNFB_Destroy` call (correct — SDK has no destroy for NFB). ✅
- `on_nfb_state_changed` — `goto cleanup` pattern, `NewLocalRef` under mutex, `DetachCurrentThread` on all return paths. Map keys `{ts, delta, theta, alpha, smr, beta}` match iOS `NfbBridge.swift:93-100` exactly. ✅
- `on_nfb_error` — same cleanup pattern, map key `{message}` matches iOS `NfbBridge.swift:107`. Null-safe message string. ✅

**Thread safety:** The `g_nfb_mutex` correctly guards both sink global refs. `NewLocalRef` under lock ensures the callback's local ref remains valid even if `dispose` concurrently deletes the global ref. No race conditions found. ✅

**Nit:** `extern void init_map_cache(JNIEnv*)` is declared (line 15) but never called in this file. Harmless but unnecessary — remove if you want to keep it clean.

#### `jni_device.cpp` (modified — `static` removal)

All 14 cache variables and 9 helper functions correctly changed from `static` to non-static (external linkage). Device-private symbols (`DeviceSlot`, `g_device_slots`, `g_device_mutex`, slot helpers, callbacks) remain `static`. ✅

No behavior change — pure linkage visibility change.

#### `CMakeLists.txt` (modified)

`jni_nfb.cpp` added to `add_library` source list. ✅

#### `NativeBridge.kt` (modified)

5 new `external fun` declarations added. Parameter types and counts match JNI function signatures exactly (verified: `Long→jlong`, `Boolean→jboolean`, `Int→jint`, `Float→jfloat`, `EventChannel.EventSink?→jobject`). ✅

#### `NfbBridge.kt` (new, 96 lines)

- `NfbStreamHandler` inner class — clean delegation pattern, mirrors `DeviceBridge.DeviceStreamHandler`. ✅
- `create()` — disposes old handle before creating new. `RuntimeException` wrapped with `parseSdkError()`. ✅
- `createCalibrated()` — extracts all 10 fields from map with safe `as? Number` casts and `0` defaults. `hasData` flag correctly gates import on the JNI side. ✅
- `dispose()` — guards on `handle != 0L`, resets after dispose. ✅

#### `DeviceBridge.kt` (modified)

`requireHandle()` changed from `private` to `public`. Needed by `NeiryKitPlugin` to pass device handle to classifier bridges. Matches iOS where `requireDevice()` is already accessible. ✅

#### `NeiryKitPlugin.kt` (modified)

- `nfbBridge` field added, instantiated in `onAttachedToEngine`. ✅
- Stream handlers registered via `nfbBridge!!.allStreamHandlers()` in `streamHandlerMap` builder — replaces `StubStreamHandler` for `nfbState`/`nfbError`. ✅
- `handleNfbCall` — guards both `nfbBridge` and `deviceBridge`, supports `create`/`createCalibrated`/`dispose`, try/catch matches `handleDeviceCall` pattern. ✅
- Teardown: `nfbBridge?.dispose()` + null before `deviceLocatorBridge?.dispose()` and `deviceBridge?.release()` — classifier torn down first. ✅

### Issues found

None.

### Verification summary

| Check | Result |
|---|---|
| Map keys match iOS parity | ✅ `{ts, delta, theta, alpha, smr, beta}`, `{message}` |
| All 10 `clCIndividualNFBData` fields populated | ✅ |
| `failReason` cast type name correct | ✅ `clCIndividualNFBCalibrationFailReason` |
| `clCNFBCalibrator_CreateOrGet` null-check | ✅ throws `"0\|..."` via `RuntimeException` |
| Separate sink setter JNI functions (not streamType dispatch) | ✅ |
| No `clCNFB_Destroy` call | ✅ correct — SDK has no destroy |
| `NewLocalRef` under mutex (not raw pointer copy) | ✅ |
| `DetachCurrentThread` on all callback return paths | ✅ via `goto cleanup` |
| Teardown order: NfbBridge before DeviceBridge/DeviceLocatorBridge | ✅ |
| `requireHandle()` exposed for classifier bridges | ✅ |

REVIEW_PASS
