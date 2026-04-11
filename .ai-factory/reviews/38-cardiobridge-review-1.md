# Code Review: CardioBridge (Android JNI + Kotlin)

**Plan:** `.ai-factory/plans/38-cardiobridge.md`
**Files reviewed:** `jni_cardio.cpp`, `CardioBridge.kt`, `NativeBridge.kt`, `NeiryKitPlugin.kt`, `CMakeLists.txt`
**Cross-referenced:** `CardioBridge.swift` (iOS), `jni_nfb.cpp` (pattern reference), Dart `CardioData.fromMap`, `PpgData.fromMap`, `channel_names.dart`, `cardio_classifier.dart`

---

## Bug: `on_cardio_ppg_data` missing null guard on `ppgData`

**File:** `jni_cardio.cpp:257-258`
**Severity:** crash at runtime

The PPG callback does not guard against a null `ppgData` handle before passing it to `clCPPGTimedData_GetCount()`:

```cpp
static void on_cardio_ppg_data(clCCardio /*cardio*/, clCPPGTimedData ppgData) noexcept {
    if (!g_jvm) return;
    // ← missing: if (!ppgData) return;
```

`clCPPGTimedData` is an opaque handle (pointer typedef). The SDK can call this callback with a null handle. `clCPPGTimedData_GetCount(nullptr)` will dereference a null pointer and crash.

This is the exact same bug that was caught in the iOS post-review fix (ROADMAP.md "CardioBridge — post-review fix" milestone). The iOS fix added `let ppgData = ppgData` to the `guard let` statement. The Android equivalent is a null check at the top of the callback.

**Fix:** Add `if (!ppgData) return;` after the `if (!g_jvm) return;` check, consistent with `on_cardio_indexes_update` which checks `if (!g_jvm || !data) return;`.

---

## Verified (no issues)

- **EventChannel IDs** — `"neiry_kit/events/cardioData"`, `"neiry_kit/events/ppgData"`, `"neiry_kit/events/cardioCalibratedEvent"` match Dart `NeiryEvents` constants and `eventChannelIds` list in `NeiryKitPlugin.kt`.
- **Map key names** — `ts`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable` match `CardioData.fromMap`; `sampleCount`, `values`, `timestamps` match `PpgData.fromMap`. iOS parity confirmed.
- **Type serialization** — `map_put_long` for timestamp (→ Dart `int`), `map_put_float` for metrics (→ Dart `double` via `num.toDouble()`), `map_put_bool` for flags (→ Dart `bool`), `map_put_int` for sampleCount (→ Dart `int`), `jfloatArray`/`jlongArray` via `map_put_object` (→ Dart `Float32List`/`Int64List`, both satisfy `List` cast in `PpgData.fromMap`).
- **JNI signatures** — All 6 `external fun` in `NativeBridge.kt` match JNI function names and parameter types in `jni_cardio.cpp`.
- **Calibrated factory path** — Follows `jni_nfb.cpp` pattern: `clCNFBCalibrator_CreateOrGet` null-check → optional import of 10-field `clCIndividualNFBData` → `clCCardio_CreateCalibrated`. All 10 fields populated.
- **Thread safety** — `pthread_mutex_t` + `NewLocalRef` under lock in all three callbacks. No raw pointer copies of global refs.
- **Cleanup paths** — `DetachCurrentThread` on all return paths (via `goto cleanup` labels). Local refs deleted in cleanup blocks.
- **Bool field casting** — `(jboolean)(data->field != 0)` correctly handles the SDK header bug where bools are initialized with `0.F`.
- **Callback error checking** — All three `clCCardio_SetOn*Event` calls correctly check `clCError*` (unlike NFB which doesn't take error params).
- **Disposal** — `nativeDisposeCardio` unregisters all three callbacks, cleans up all three sinks under mutex. No `clCCardio_Destroy` (doesn't exist in SDK). Disposal order in `onDetachedFromEngine`: cardio → physio → emotions → nfbCalibrator → nfb → device (correct: classifiers before infrastructure).
- **Plugin wiring** — All 5 integration points: field, init, streamHandlerMap, handleCardioCall dispatch, onDetachedFromEngine cleanup. `handleCardioCall` dispatch pattern matches `handleNfbCall` exactly.
- **CMakeLists.txt** — `jni_cardio.cpp` added to source list after `jni_physio.cpp`.
- **Extern declarations** — All helpers (`make_map`, `map_put_float`, `map_put_long`, `map_put_bool`, `map_put_int`, `map_put_object`, `throw_sdk_error`) declared extern only, not redefined. Globals (`g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`) declared extern from `jni_device_locator.cpp`.
