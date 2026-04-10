# Plan Review: 37-physiobridge

**Plan:** PhysioBridge — Android JNI + Kotlin bridge for PhysiologicalStates classifier
**Files Reviewed:** 14 (plan + 13 codebase files)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Architecture shows a `classifiers/` subdirectory under `android/src/main/kotlin/.../`, but actual codebase places bridge files flat alongside `NeiryKitPlugin.kt` (e.g. `EmotionsBridge.kt`). Plan correctly follows the *actual* layout, not the aspirational one. No action needed in this plan.
- **RULES.md:** File does not exist. `WARN` — no blocking criteria.
- **ROADMAP.md:** Plan directly implements the `PhysioBridge` milestone under "Android bridges". All four event channels, baselines import/export, and the "no Destroy" pattern match the roadmap description. ✓

## Verification Summary

### C API contract — all signatures confirmed against `CPhysiologicalStates.h`

| Plan reference | C header | Match |
|---|---|---|
| `clCPhysiologicalStates_Create(dev, &error)` | line 35 | ✓ |
| `clCPhysiologicalStates_StartBaselineCalibration(physio)` — no error param | line 37 | ✓ |
| `clCPhysiologicalStates_ImportBaselines(physio, &baselines)` — no error param | line 36 | ✓ |
| `SetOnStatesUpdateEvent(physio, handler, &error)` — takes `clCError*` | line 40 | ✓ |
| `SetOnCalibratedEvent(physio, handler, &error)` — takes `clCError*` | line 43 | ✓ |
| `SetOnCalibrationProgressUpdateEvent(physio, handler, &error)` — takes `clCError*` | line 46 | ✓ |
| `SetOnIndividualNFBUpdateEvent(physio, handler, &error)` — takes `clCError*` | line 49 | ✓ |
| `clCPhysiologicalStates_Value` struct: 9 fields (ts, relaxation, fatigue, none, concentration, involvement, stress, nfbArtifacts, cardioArtifacts) | lines 14–24 | ✓ |
| `clCPhysiologicalStates_Baselines` struct: 6 fields (timestampMilli, alpha, beta, alphaGravity, betaGravity, concentration) | lines 26–33 | ✓ |

### Event channel names — verified against Dart contract and plugin registration

| Plan channel ID | `channel_names.dart` | `NeiryKitPlugin.kt` eventChannelIds |
|---|---|---|
| `neiry_kit/events/physiologicalState` | `NeiryEvents.physiologicalState` ✓ | line 82 ✓ |
| `neiry_kit/events/physiologicalCalibrationProgress` | `NeiryEvents.physiologicalCalibrationProgress` ✓ | line 90 ✓ |
| `neiry_kit/events/physiologicalCalibrated` | `NeiryEvents.physiologicalCalibrated` ✓ | line 91 ✓ |
| `neiry_kit/events/physiologicalIndividualNfb` | `NeiryEvents.physiologicalIndividualNfb` ✓ | line 92 ✓ |

### Dart model contract — map keys match

- `PhysiologicalStatesValue.fromMap` reads: `ts`, `relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress`, `nfbArtifacts` (bool), `cardioArtifacts` (bool) — plan's `on_physio_state_changed` emits exactly these 9 keys. ✓
- `PhysiologicalStatesBaselines.fromMap` reads: `ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration` — plan's `on_physio_calibrated` emits exactly these 6 keys. ✓
- Calibration progress: Dart reads `map['progress'] as num` — plan emits `map_put_float("progress", clamped)`. ✓
- Individual NFB: Dart maps `(_) {}` (ignores content) — plan emits empty map. ✓

### JNI infrastructure — dependencies verified

- `map_put_bool` exists at `jni_device.cpp:165`, non-static, uses `Boolean.valueOf(Z)` via cached `s_boolClass`/`s_boolValueOf` (initialized in `init_map_cache`). This will be the **first production usage** of `map_put_bool` — implementation looks correct but was previously untested.
- `make_map`, `map_put_float`, `map_put_long` — all non-static, already used by `jni_emotions.cpp` and `jni_nfb.cpp`. ✓
- `throw_sdk_error`, `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess` — all externed by other JNI files. ✓

### iOS parity — verified against `PhysioBridge.swift`

- 4 stream handlers (state, calibrationProgress, calibrated, individualNfb) — plan matches. ✓
- `create` → `Create` + register 4 callbacks with error checking — plan matches. ✓
- `startBaselineCalibration` → no error param — plan matches. ✓
- `importBaselines` → 6-field map → C struct — plan matches. ✓
- `dispose` → unregister callbacks (no Destroy) — plan matches. ✓
- Progress clamped to [0.0, 1.0] — plan matches. ✓
- Individual NFB emits empty map — plan matches. ✓

### Plugin wiring — verified against `NeiryKitPlugin.kt`

- `handlePhysiologicalCall` is currently a stub (`result.notImplemented()` at line 334) — plan replaces it. ✓
- Method channel `"neiry_kit/physiological"` is already registered (line 40). ✓
- Teardown in `onDetachedFromEngine` — plan adds `physioBridge?.dispose()` before `emotionsBridge?.dispose()`. Correct: classifiers before device/locator. ✓
- `CMakeLists.txt` source list — plan adds `jni_physio.cpp` after `jni_emotions.cpp`. ✓

### Method dispatch — Dart → Kotlin argument keys verified

- `create`: Dart sends `{serial: ...}` — plan ignores serial, uses `devBridge.requireHandle()`. Matches emotions pattern. ✓
- `startBaselineCalibration`: Dart sends `{serial: ...}` — plan ignores serial. ✓
- `importBaselines`: Dart sends `{serial: ..., baselines: {...}}` — plan extracts `"baselines"` key. Matches `NeiryArgs.baselines`. ✓
- `dispose`: Dart sends `{serial: ...}` — plan ignores serial. ✓

## Critical Issues

None.

## Observations (non-blocking)

1. **First usage of `map_put_bool`** — The `nfbArtifacts`/`cardioArtifacts` bool fields make PhysioBridge the first consumer of `map_put_bool` in the JNI layer. The implementation uses `Boolean.valueOf(jboolean)` via cached JNI refs and looks correct, but this code path has never been exercised at runtime. If a subtle issue exists (e.g. `jboolean` casting edge case), it will surface here first.

2. **Key difference from EmotionsBridge template** — Task 1 says "following the exact structure of `jni_emotions.cpp`" but PhysiologicalStates has two structural differences: (a) 4 sinks vs. Emotions' 2, and (b) `SetOn*Event` calls require `clCError*` + error checking, where Emotions' callbacks take no error param. The plan correctly describes both differences in detail, so the "exact structure" phrasing is about file layout rather than identical code.

3. **Partial callback registration failure** — If `nativeCreatePhysio` registers the first callback successfully but a later registration fails, the native handle is orphaned (never returned, no Destroy function). However, this is safe: null sinks cause all callbacks to no-op via the `NewLocalRef` guard pattern, and the SDK manages handle lifetime internally. This matches the iOS implementation's behavior.

## Positive Notes

- Thorough plan with exact field names, map keys, and type casts specified — reduces ambiguity for the implementer.
- Correct identification that PhysiologicalStates `SetOn*Event` functions take `clCError*` while Emotions' do not — this is a critical API difference that's easy to get wrong.
- Callback patterns (mutex + `NewLocalRef` + `goto cleanup` + `DetachCurrentThread`) correctly follow the established JNI safety conventions from prior bridges.
- Commit plan separates JNI layer (commits 1) from Kotlin + wiring (commit 2), which is a clean boundary for review.
- The `importBaselines` JNI function correctly passes individual typed parameters rather than parsing a Java map in C++ — cleaner and safer.

PLAN_REVIEW_PASS
