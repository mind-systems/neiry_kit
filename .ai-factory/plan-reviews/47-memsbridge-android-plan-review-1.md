## Code Review Summary

**Plan Reviewed:** `.ai-factory/plans/47-memsbridge-android.md`
**Files Analyzed:** 10 (plan + 9 codebase reference files)
**Risk Level:** Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — no violations detected. Plan follows "one bridge class per C API module" and "platform bridges must never cross-call each other" rules. MEMS bridge gets its own JNI file, Kotlin class, and channel IDs.
- **RULES.md:** WARN — file does not exist. No blocking rules to check.
- **ROADMAP.md:** No issues. This plan implements the single unchecked item under "MEMS classifier" — `MEMSBridge Android`. The plan scope matches the milestone description exactly.

### Critical Issues

**1. Wrong C API function name for calibration import (Task 1, step 2)**

The plan says:
> call `clCNFBCalibrator_Import(calibrator, &nfbData)`

The actual function (used in `jni_cardio.cpp:109`) is:
```cpp
clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError);
```

Two problems: wrong function name, and the third `clCError*` parameter is omitted. Without the error check, a failed import would silently continue and create the classifier with stale/empty calibration data.

**2. Wrong callback parameter type (Task 1, Callback section)**

The plan declares:
> `on_mems_data(clCMEMS, clCMEMSTimedData* memsData)`

The `*` is incorrect. `clCMEMSTimedData` is already a typedef pointer (opaque handle), matching `clCPPGTimedData` in the Cardio analogue (`jni_cardio.cpp:257`):
```cpp
static void on_cardio_ppg_data(clCCardio, clCPPGTimedData ppgData) noexcept;
```

Using `clCMEMSTimedData*` would be a pointer-to-pointer, and the `clCMEMSTimedData_GetCount(memsData)` / `clCMEMSTimedData_GetAccelerometer(memsData, i)` accessor calls would fail to compile because they expect `clCMEMSTimedData`, not `clCMEMSTimedData*`.

Correct signature:
```cpp
static void on_mems_data(clCMEMS, clCMEMSTimedData memsData) noexcept;
```

### Suggestions

**3. Missing `noexcept` on callback declaration**

All existing callbacks use `noexcept` (`jni_cardio.cpp:35-37`). The plan's callback description omits it. Should be `on_mems_data(clCMEMS, clCMEMSTimedData memsData) noexcept`.

**4. Missing `uintptr_t` intermediate cast**

The plan says `(clCDevice)deviceHandle` but the established pattern throughout the codebase is `(clCDevice)(uintptr_t)deviceHandle` (see `jni_cardio.cpp:47`). The intermediate `uintptr_t` cast suppresses the sign-extension warning when converting `jlong` (signed 64-bit) to a pointer type.

**5. Missing null guard on handle in `nativeDisposeMems`**

Cardio's dispose (`jni_cardio.cpp:187`) starts with:
```cpp
if (cardioHandle == 0) return;
```

The plan's `nativeDisposeMems` description jumps straight to clearing the callback without guarding `memsHandle == 0`. Calling `clCMEMS_SetOnMEMSTimedDataUpdateEvent` with a null handle would likely crash.

**6. Missing null check on `g_memsDataSink` before `DeleteGlobalRef` in dispose**

The plan says "Lock mutex, `DeleteGlobalRef(g_memsDataSink)`, set to nullptr, unlock." But `DeleteGlobalRef(nullptr)` causes a JNI abort. The Cardio pattern (`jni_cardio.cpp:196-199`) always null-checks first:
```cpp
if (g_cardioStateSink) {
    env->DeleteGlobalRef(g_cardioStateSink);
    g_cardioStateSink = nullptr;
}
```

**7. ArrayList construction details missing from callback**

The plan says "Use `ArrayList` + `add()` for the list" but doesn't specify the JNI mechanics. The implementer needs `FindClass("java/util/ArrayList")`, `GetMethodID` for `<init>` and `add`, and `NewObject` — all within the callback. This exact pattern already exists in `jni_device_locator.cpp:33-36` (`marshal_device_list`) and can be followed directly. More importantly: each sample map created via `make_map(env)` inside the loop **must** be `DeleteLocalRef`'d immediately after `CallBooleanMethod(list, alAdd, sampleMap)` — not deferred to `cleanup:`. Deferring would require tracking N map refs and risks overflowing the JNI local ref table for large batches. The `marshal_device_list` function demonstrates this correctly (line 77).

**8. Unnecessary `serial` extraction in `handleMemsCall` (Task 5)**

The plan says to "extract `serial` from args" in the `create` handler. No other classifier handler does this — they all just call `devBridge.requireHandle()` directly (see `handleCardioCall` at `NeiryKitPlugin.kt:391-393`, and iOS `handleMemsCall` which also ignores `serial`). The `serial` arg is consumed only by the Dart `EventChannel.receiveBroadcastStream()` call, not by the MethodChannel. Not a bug, but dead code.

### Positive Notes

- The plan correctly identifies `jni_cardio.cpp` + `CardioBridge.kt` as the closest analog and mirrors their structure faithfully.
- Threading model is correctly specified: `pthread_mutex_t` guarding global sink refs, `NewLocalRef` under lock (not raw pointer copy), `DetachCurrentThread` on all return paths, `goto cleanup` pattern.
- The extern declaration block is accurate — all helpers come from `jni_device.cpp` / `jni_device_locator.cpp` and the plan correctly says "do NOT redefine."
- EventChannel ID `"neiry_kit/events/memsData"` matches the existing constant in `channel_names.dart` and is already registered (with `StubStreamHandler`) in `NeiryKitPlugin.kt:103`. The plan correctly wires a real handler to replace the stub.
- The plan correctly identifies that MEMS data accessor functions (`GetCount`, `GetAccelerometer`, `GetGyroscope`, `GetTimestampMilli`) take no `clCError*`, while `SetOnMEMSTimedDataUpdateEvent` does take `clCError*`.
- Map keys (`ax/ay/az/gx/gy/gz/ts`) match `MemsSample.fromMap()` exactly.
- The Dart side expects `raw as List` of maps — the plan's ArrayList approach is consistent with this and with the established `marshal_device_list` precedent.
- Two-commit strategy is clean and maps logically to JNI layer vs Kotlin+plugin wiring.
- iOS parity is well-maintained: same factory paths (plain + calibrated), same `allStreamHandlers()` pattern, same dispose semantics.
