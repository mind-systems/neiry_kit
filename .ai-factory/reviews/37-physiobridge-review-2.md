# Code Review: 37-physiobridge (round 2)

**Scope:** `jni_physio.cpp`, `PhysioBridge.kt`, `NativeBridge.kt`, `NeiryKitPlugin.kt`, `CMakeLists.txt`
**Reviewed against:** iOS `PhysioBridge.swift`, `jni_emotions.cpp` (reference pattern), Dart models (`PhysiologicalStatesValue.fromMap`, `PhysiologicalStatesBaselines.fromMap`/`toMap`), Dart channel contract (`ClassifierMethods`, `NeiryArgs`, `NeiryEvents`), C SDK headers

## Previous review fix verified

The one bug from review 1 (nullptr `clCError*` in `nativeDisposePhysio`) has been fixed. Lines 165–169 now declare `clCError err = {};` and pass `&err` to all four `SetOn*Event` unregistration calls, matching iOS `PhysioBridge.swift:143–149`.

## Full verification

### JNI map keys ↔ Dart `fromMap` keys

**`on_physio_state_changed` → `PhysiologicalStatesValue.fromMap`:**
`ts` (long→int), `relaxation/fatigue/none/concentration/involvement/stress` (float→double via `orNull`), `nfbArtifacts/cardioArtifacts` (bool→bool) — all 9 keys match.

**`on_physio_calibrated` → `PhysiologicalStatesBaselines.fromMap`:**
`ts` (long→int), `alpha/beta/alphaGravity/betaGravity/concentration` (float→double via `orNull`) — all 6 keys match.

**`PhysiologicalStatesBaselines.toMap` → `PhysioBridge.kt::importBaselines` → `nativeImportBaselines`:**
`ts` (int→Long→jlong→int64_t), `alpha/beta/alphaGravity/betaGravity/concentration` (double→Float→jfloat→float) — all 6 keys extracted correctly. Type narrowing from 64-bit to 32-bit float matches the C struct definition.

**`on_physio_calibration_progress` → Dart `(map['progress'] as num).toDouble()`:**
Single `progress` key (float→double) — matches.

**`on_physio_individual_nfb_update` → Dart `.map((_) {})`:**
Empty map — Dart side ignores payload — matches.

### Channel names — cross-platform parity

| Channel | Android `PhysioBridge.kt` | iOS `PhysioBridge.swift` | Dart `NeiryEvents` |
|---|---|---|---|
| state | `neiry_kit/events/physiologicalState` | `neiry_kit/events/physiologicalState` | ✓ |
| progress | `neiry_kit/events/physiologicalCalibrationProgress` | `neiry_kit/events/physiologicalCalibrationProgress` | ✓ |
| calibrated | `neiry_kit/events/physiologicalCalibrated` | `neiry_kit/events/physiologicalCalibrated` | ✓ |
| nfb | `neiry_kit/events/physiologicalIndividualNfb` | `neiry_kit/events/physiologicalIndividualNfb` | ✓ |

### Method dispatch — Dart ↔ Android ↔ iOS

| Dart `ClassifierMethods` | Android `handlePhysiologicalCall` | iOS `handlePhysiologicalCall` |
|---|---|---|
| `create` | ✓ | ✓ |
| `startBaselineCalibration` | ✓ | ✓ |
| `importBaselines` (arg key: `baselines`) | ✓ `(map["baselines"])` | ✓ `(args["baselines"])` |
| `dispose` | ✓ | ✓ |

### Thread safety

- All 4 callbacks: `GetEnv`/`AttachCurrentThread` → `NewLocalRef` under `g_physio_mutex` → `goto cleanup` with `DeleteLocalRef` + `DetachCurrentThread` — matches established `jni_emotions.cpp` pattern exactly.
- Sink setters: `DeleteGlobalRef` → `NewGlobalRef` under single mutex — correct.
- Dispose: unregisters callbacks (prevents new dispatches), then locks mutex to clear sinks — in-flight callbacks that already acquired local refs complete safely.

### Error handling

- `nativeCreatePhysio`: all 4 `SetOn*Event` calls check `error.success`, `throw_sdk_error` on failure — correct (these take `clCError*`).
- `nativeStartBaselineCalibration`: no error param — correct per C header.
- `nativeImportBaselines`: no error param — correct per C header.
- `nativeDisposePhysio`: passes `&err`, ignores result — correct, matches iOS.
- Kotlin `create()`: wraps in try/catch `RuntimeException` → `parseSdkError` — matches `EmotionsBridge.kt`.

### Plugin wiring

- `physioBridge` constructed after `emotionsBridge` in `onAttachedToEngine` — correct.
- Stream handlers added to `streamHandlerMap` — all 4 channels will get real handlers instead of stubs.
- Teardown order in `onDetachedFromEngine`: physio → emotions → calibrator → nfb → locator → device — classifiers before infrastructure, correct.
- `CMakeLists.txt`: `jni_physio.cpp` added to source list — correct.

### Extern declarations

`make_map`, `map_put_float`, `map_put_long`, `map_put_bool` declared extern from `jni_device.cpp`. No redefinition of helpers or JNI cache vars. `map_put_bool` is newly used (not used by `jni_emotions.cpp`) — confirmed it exists in `jni_device.cpp:165`.

REVIEW_PASS
