# Code Review: CardioBridge (Android JNI + Kotlin) — Review 2

**Plan:** `.ai-factory/plans/38-cardiobridge.md`
**Files reviewed:** `jni_cardio.cpp` (349 lines), `CardioBridge.kt` (99 lines), `NativeBridge.kt` (new section, 21 lines), `NeiryKitPlugin.kt` (full 450 lines), `CMakeLists.txt` (25 lines)
**Cross-referenced:** `CardioBridge.swift` (iOS), `jni_nfb.cpp` (pattern), `CardioData.fromMap`, `PpgData.fromMap`, `channel_names.dart`, `cardio_classifier.dart`

---

## Review 1 finding status

| Finding | Status |
|---|---|
| `on_cardio_ppg_data` missing null guard on `ppgData` | **Fixed** — line 258 now reads `if (!g_jvm \|\| !ppgData) return;` |

## Verification checklist

- **Extern declarations** — 4 globals + 6 map helpers + `throw_sdk_error`. All `extern` only, none redefined. Matches `jni_physio.cpp` / `jni_emotions.cpp` pattern. ✓
- **Plain factory (`nativeCreateCardio`)** — `clCCardio_Create` + error check + three callback registrations each with `clCError*` check. Correct per SDK header (`SetOn*Event` all take `clCError*`). ✓
- **Calibrated factory (`nativeCreateCardioCalibrated`)** — `clCNFBCalibrator_CreateOrGet` null check → optional 10-field `clCIndividualNFBData` import → `clCCardio_CreateCalibrated` → three callback registrations. Matches `jni_nfb.cpp` calibrated pattern exactly. All 10 struct fields populated. `failReason` cast to `clCIndividualNFBCalibrationFailReason`. ✓
- **Sink setters** — Three functions, all follow lock → DeleteGlobalRef old → NewGlobalRef new → unlock pattern. ✓
- **Dispose** — Guard `handle == 0`, unregister three callbacks with nullptr, clean three sinks under mutex. No `clCCardio_Destroy` (correct — doesn't exist in SDK). ✓
- **Indexes callback** — Null guard on `data`. Map keys `ts/heartRate/stressIndex/kaplanIndex/hasArtifacts/skinContact/motionArtifacts/metricsAvailable` match iOS and Dart `CardioData.fromMap`. Bool fields cast `(jboolean)(data->field != 0)`. ✓
- **PPG callback** — Null guard on `ppgData` (review 1 fix). Accessor pattern: `GetCount`→`GetValue`→`GetTimestampMilli`. Arrays via `NewFloatArray`/`NewLongArray` + heap buffers + `Set*ArrayRegion`. Map keys `sampleCount/values/timestamps` match iOS and Dart `PpgData.fromMap`. ✓
- **Calibrated callback** — Empty map dispatch matching iOS `[:]`. ✓
- **Thread safety** — All three callbacks: attach-if-detached, mutex + `NewLocalRef` under lock, null guard → goto cleanup, `DeleteLocalRef` all refs, `DetachCurrentThread` if attached. ✓
- **JNI function names** — All 6 use `neiry_1kit` encoding. No `FindClass` calls with underscore-containing package paths (only `java/lang/RuntimeException`). ✓
- **NativeBridge.kt signatures** — 6 `external fun` declarations. Parameter types align with JNI: `Long↔jlong`, `Boolean↔jboolean`, `Float↔jfloat`, `Int↔jint`. ✓
- **CardioBridge.kt** — Stream handlers wired to correct native sink setters. `allStreamHandlers()` returns 3 channel IDs matching `NeiryEvents` constants and `eventChannelIds` list. Factory methods catch `RuntimeException` and wrap with `parseSdkError`. Calibrated path unpacks all 10 fields. ✓
- **NeiryKitPlugin.kt** — Field, init, streamHandlerMap, `handleCardioCall` dispatch (create/createCalibrated/dispose), and `onDetachedFromEngine` cleanup. Disposal order correct: cardio → physio → emotions → nfbCalibrator → nfb → deviceLocator/device. ✓
- **CMakeLists.txt** — `jni_cardio.cpp` in source list after `jni_physio.cpp`. ✓
- **Type serialization chain** — `map_put_long(ts)` → Dart `int`; `map_put_float(heartRate)` → Dart `double` via `(as num).toDouble()`; `map_put_bool(hasArtifacts)` → Dart `bool`; `jfloatArray` → Dart `Float32List` (satisfies `List` cast); `jlongArray` → Dart `Int64List` (satisfies `List` cast); `map_put_int(sampleCount)` → Dart `int`. ✓
- **iOS parity** — EventChannel IDs, map keys, callback semantics, calibrated factory path, and disposal behavior all match `CardioBridge.swift`. ✓

REVIEW_PASS
