## Code Review: NfbCalibratorBridge (Android)

**Plan:** `.ai-factory/plans/35-nfbcalibratorbridge.md`
**Files reviewed:** 6 changed/new files + 10 reference files (iOS bridge, Dart API, C headers, existing JNI/Kotlin bridges)

### Files Changed

| File | Type | Lines |
|---|---|---|
| `android/src/main/cpp/jni_device_locator.cpp` | modified | 1 (static → non-static) |
| `android/src/main/cpp/CMakeLists.txt` | modified | 1 (new source) |
| `android/src/main/cpp/jni_nfb_calibrator.cpp` | **new** | 301 |
| `android/src/main/kotlin/.../NativeBridge.kt` | modified | +16 (external fun declarations) |
| `android/src/main/kotlin/.../NfbCalibratorBridge.kt` | **new** | 95 |
| `android/src/main/kotlin/.../NeiryKitPlugin.kt` | modified | +50 (bridge wiring + dispatch) |

### Verification Performed

**JNI ↔ Kotlin contract:** All 6 JNI function signatures verified against `NativeBridge.kt` external fun declarations — mangled names (`neiry_1kit`), parameter types (`jlong`/`jboolean`/`jfloat`/`jobject`), and return types match.

**Dart ↔ Android method dispatch:** All 5 `NFBCalibratorMethods` strings (`startCalibration`, `stopCalibration`, `importCalibration`, `getCalibration`, `isCalibrated`) verified against `handleNfbCalibratorCall`. Argument extraction for `NeiryArgs.calibratorData` handles both modes:
- Full mode: `call.arguments` is null → `calibratorData` is null → `quick = false` ✅
- Quick mode: `call.arguments` is `{'calibratorData': 'quick'}` → `quick = true` ✅
- Import: `call.arguments` is `{'calibratorData': {...map...}}` → cast to `Map<String, Any>` ✅

**Map structure ↔ Dart deserialization:**
- Stage event: `{"type": "stage", "stage": int}` → `CalibrationEvent.deserialize` dispatches to `CalibrationStageFinished(CalibrationStage.fromCode(int))`. JNI emits `g_currentStage` (0-3) before incrementing — matches `CalibrationStage.fromCode` range. ✅
- Done event: `{"type": "done", "data": {...10 fields...}}` → `CalibrationCompleted(IndividualNfbData.fromMap(...))`. Nested map via `map_put_object`. All 10 fields present with correct types: `ts` as `jlong` → Dart `int`, `failReason` as `jint` → Dart `int`, 8 floats as `jfloat` → Dart `double` (via `(num).toDouble()`). ✅
- `nativeGetCalibration` return: same 10-field HashMap, returned via MethodChannel → `IndividualNfbData.fromMap`. ✅

**iOS parity:** Verified Android dispatch against `NeiryKitPlugin.swift:352-410` — same 5 methods, same argument keys, same error handling shape. `NfbCalibratorBridge.kt` methods mirror `NfbCalibratorBridge.swift` methods one-to-one. Stage tracking logic (`g_currentStage` increment + manual `CalibrateIndividualNFB` re-entry) matches iOS exactly.

**Thread safety:**
- EventSink `g_calibrationSink` guarded by `pthread_mutex_t` + `NewLocalRef` snapshot pattern — matches `jni_nfb.cpp` established pattern. ✅
- `DetachCurrentThread` called on all callback paths via `goto cleanup`. ✅
- `g_calibrator`/`g_currentStage`/`g_isQuickMode` written by JNI functions on main thread, read by callbacks on SDK background thread. Write order is safe: all state set before `CalibrateIndividualNFB` starts the SDK. `nativeStopCalibration` unregisters callbacks before any state could be read again. Same single-writer pattern as iOS. ✅

**SDK API correctness:**
- `clCNFBCalibrator_CreateOrGet` null-checked with `ThrowNew(RuntimeException, "0|...")` ✅
- `clCNFBCalibrator_IsCalibrated` / `HasCalibrationFailed` — no `clCError*` wrapping ✅
- `clCNFBCalibrator_CalibrateIndividualNFB` stage enum cast `(clCIndividualNFBCalibrationStage)g_currentStage` — values 0-3 match `clCIndividualNFBCalibrationStage_1` through `_4` ✅
- Calibrator handle never destroyed (SDK-managed lifecycle) ✅
- `clCIndividualNFBData` all 10 fields populated in import and emitted in callbacks ✅

**Extern declarations:** Verified `g_postError` is now non-static at `jni_device_locator.cpp:18`. All other externs (`g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`, map helpers, `throw_sdk_error`) verified as non-static in their definition files.

**Teardown order:** `onDetachedFromEngine` disposes calibrator before NFB classifier — correct dependency order (calibrator feeds classifier).

**`g_postError` call:** Verified argument structure against existing call at `jni_device_locator.cpp:128-129` — identical 5-arg pattern `(handler, sink, code_jstring, message_jstring, nullptr)`. Method signature `(Handler, Object, String, String, Object)V` matches.

### Critical Issues

None.

### Minor Notes (not blocking)

**1. Dead ternary on `error.message` (jni_nfb_calibrator.cpp:237)**

```c
jstring jMessage = env->NewStringUTF(error.message ? error.message : "");
```

`clCError.message` is `char[256]` (fixed-size array, `CError.h:29`), so the array-to-pointer decay is always non-null. The ternary is dead code. Harmless — `throw_sdk_error` at `jni_device_locator.cpp:25` uses `error->message` directly without the check. Style inconsistency only.

REVIEW_PASS
