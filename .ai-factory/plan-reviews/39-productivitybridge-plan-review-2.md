## Plan Review: ProductivityBridge (Android JNI + Kotlin)

**Files Reviewed:** 12 (plan + SDK header + 4 JNI references + 4 Kotlin references + 2 Dart models + iOS ProductivityBridge)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered SDK bridge pattern (JNI C++ → Kotlin Bridge → Plugin wiring). No dependency violations. Each bridge owns its own channels.
- **RULES.md:** N/A (file does not exist).
- **ROADMAP.md:** PASS — plan implements the exact milestone "ProductivityBridge" with all noted constraints (no `clCError*` on `SetOn*Event`, `resetAccumulatedFatigue` takes `clCError*`, two factory paths, 10-field `clCIndividualNFBData`).

### Critical Issues

None.

### Verification Against SDK Header (`CProductivity.h`)

All C API function signatures in the plan match the SDK header exactly:

- `clCProductivity_Create(device, &error)` — `clCError*` ✓
- `clCProductivity_CreateWithIndividualData(device, &data, &error)` — takes `clCIndividualNFBData*` + `clCError*` ✓
- All five `SetOn*Event` functions — void, no `clCError*` param ✓
- `clCProductivity_ImportBaselines(prod, &baselines, &error)` — `clCError*` ✓
- `clCProductivity_ResetAccumulatedFatigue(prod, &error)` — `clCError*` ✓
- `clCProductivity_StartBaselineCalibration(prod)` — no error ✓
- No `SetOnErrorEvent` declared in header — correct to omit error sink ✓

### Verification Against Existing Patterns

| Aspect | Reference file | Plan matches? |
|--------|---------------|---------------|
| JNI extern declarations | `jni_cardio.cpp` (includes `map_put_int`, `map_put_object`) | ✓ |
| Mutex + global sink pattern | `jni_physio.cpp` | ✓ |
| Callback boilerplate (attach/lock/guard/dispatch/cleanup) | `jni_physio.cpp` | ✓ |
| Two-factory JNI path | `jni_cardio.cpp` (`nativeCreateCardioCalibrated`) | ✓ |
| Kotlin bridge class shape | `CardioBridge.kt` + `PhysioBridge.kt` | ✓ |
| Plugin wiring (`streamHandlerMap`, `handleProductivityCall`) | `NeiryKitPlugin.kt` | ✓ |
| `NativeBridge.kt` external fun section | Existing cardio/physio sections | ✓ |
| CMakeLists source list | `CMakeLists.txt` line 15 | ✓ |

### Verification Against iOS Parity

- Dual-dispatch in baselines callback (structured map → `baselinesSink` + raw bytes → `calibratedSink`) matches `ProductivityBridge.swift` lines 147–167 ✓
- `importBaselines` as raw bytes blob with size validation matches iOS `importBaselines(data:)` ✓
- Event channel IDs match those already registered in `NeiryKitPlugin.kt` ✓
- `productivityError` channel handled by `StubStreamHandler` (no SDK error callback) ✓

### Verification Against Dart Layer

- `ProductivityMetrics.fromMap` keys: `ts`, `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`, `fatigueGrowthRate`, `artifactsData` — all emitted by Task 5 ✓
- `ProductivityIndexes.fromMap` keys: `ts`, `relaxation`, `stress`, `hasArtifacts`, `gravityBaseline`, `productivityBaseline`, `fatigueBaseline`, `reverseFatigueBaseline`, `relaxationBaseline`, `concentrationBaseline` — all emitted by Task 6 ✓
- `ProductivityBaselines.fromMap` keys: `ts`, `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration` — all emitted by Task 7 ✓
- `calibrated` stream expects `map['baselines'] as Uint8List` — Task 7 sends `jbyteArray` under key `"baselines"` ✓
- `calibrationProgress` expects `map['progress']` — Task 7 sends float under key `"progress"` ✓

### Positive Notes

- Plan correctly identifies the key architectural difference between Productivity and Cardio calibrated factories: Productivity uses `CreateWithIndividualData` directly (no calibrator handle), while Cardio uses `clCNFBCalibrator_CreateOrGet` + `CreateCalibrated`. This avoids a subtle bug.
- The dual-dispatch baselines callback is well-documented with explicit iOS cross-reference.
- All callback signatures verified against the header — no `clCError*` confusion.
- Raw bytes round-trip for baselines is well-explained (serialize struct → bytes → Dart `Uint8List` → bytes → reinterpret back to struct).
- Correct decision to exclude `hasCalibrationData` boolean (unlike Cardio) since this factory is only called when data exists.
- Task dependencies are correctly sequenced.

PLAN_REVIEW_PASS
