# Code Review: 37-physiobridge

**Scope:** `jni_physio.cpp`, `PhysioBridge.kt`, `NativeBridge.kt`, `NeiryKitPlugin.kt`, `CMakeLists.txt`
**Reviewed against:** iOS `PhysioBridge.swift`, `jni_emotions.cpp` (reference pattern), Dart channel contract, C SDK headers

## Findings

### 1. BUG — `nullptr` error pointer in `nativeDisposePhysio` will crash

**File:** `android/src/main/cpp/jni_physio.cpp`, lines 165–168
**Severity:** high

```cpp
clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nullptr, nullptr);
clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nullptr, nullptr);
clCPhysiologicalStates_SetOnCalibratedEvent(physio, nullptr, nullptr);
clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nullptr, nullptr);
```

All four `clCPhysiologicalStates_SetOn*Event` functions take `clCError*` as their third parameter. Passing `nullptr` will cause a null pointer dereference if the SDK writes to the error struct without null-checking (which is the common C SDK behavior for output parameters).

iOS (`PhysioBridge.swift:143–149`) creates a valid local error variable and passes its address:
```swift
var e = clCError()
clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nil, &e)
```

**Fix:** Declare a local `clCError` and pass its address. Errors can still be ignored on teardown:
```cpp
clCError err = {};
clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nullptr, &err);
clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nullptr, &err);
clCPhysiologicalStates_SetOnCalibratedEvent(physio, nullptr, &err);
clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nullptr, &err);
```

## Verified correct

- **Channel names** — All 4 EventChannel IDs (`physiologicalState`, `physiologicalCalibrationProgress`, `physiologicalCalibrated`, `physiologicalIndividualNfb`) match Dart `NeiryEvents`, iOS `PhysioBridge.swift`, and `NeiryKitPlugin.swift` exactly.
- **MethodChannel method names** — `create`, `startBaselineCalibration`, `importBaselines`, `dispose` match Dart `ClassifierMethods` constants and iOS dispatch.
- **Map keys** — `on_physio_state_changed` emits 9 fields matching iOS: `ts`, `relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress`, `nfbArtifacts`, `cardioArtifacts`. `on_physio_calibrated` emits 6 fields matching iOS: `ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`.
- **Bool fields** — `nfbArtifacts`/`cardioArtifacts` use `map_put_bool` with `(jboolean)` cast, matching the `clCPhysiologicalStates_Value` struct definition.
- **Calibration progress clamping** — `fmaxf(0.0f, fminf(1.0f, progress))` matches the specification and iOS behavior.
- **Individual NFB update** — Emits empty map `{}` as specified (no data payload), matching iOS `bridge.individualNfbHandler.send([:])`.
- **Baselines import** — `nativeImportBaselines` populates `clCPhysiologicalStates_Baselines` struct with all 6 fields and passes `&baselines` (valid pointer). `ImportBaselines` has no `clCError*` parameter — correctly not error-checked.
- **`StartBaselineCalibration`** — No error parameter in C API, correctly not error-checked.
- **Mutex / NewLocalRef / DetachCurrentThread** — All 4 callbacks follow the established `jni_emotions.cpp` pattern exactly: `GetEnv`/`AttachCurrentThread`, `NewLocalRef` under mutex lock, `goto cleanup` with `DeleteLocalRef` + `DetachCurrentThread`.
- **Extern declarations** — `make_map`, `map_put_float`, `map_put_long`, `map_put_bool` correctly declared `extern` from `jni_device.cpp`. No redefinition of helpers or cache vars.
- **`nativeCreatePhysio` error handling** — Each `SetOn*Event` call checks `error.success` and throws on failure. The reuse of a single `clCError` variable across sequential calls is safe (the SDK overwrites on each call).
- **PhysioBridge.kt** — Structurally mirrors `EmotionsBridge.kt`. Handle guard, `parseSdkError` wrapping, `importBaselines` field extraction all correct.
- **NeiryKitPlugin.kt** — `handlePhysiologicalCall` dispatches all 4 methods matching iOS. `importBaselines` extracts nested `baselines` map from arguments matching Dart's `{NeiryArgs.baselines: baselines.toMap()}`. Dispose order (physio before emotions before device bridges) is correct.
- **NativeBridge.kt** — All 8 `external fun` signatures match their JNI counterparts in parameter types and count.
- **CMakeLists.txt** — `jni_physio.cpp` added to source list.
