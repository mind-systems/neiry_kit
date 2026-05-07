## Code Review Summary

**Plan:** `.ai-factory/plans/47-memsbridge-android.md`
**Files Changed:** 5 (1 new C++, 1 new Kotlin, 3 modified)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** No violations. MEMS bridge follows "one bridge class per C API module" rule — own JNI file, own Kotlin class, own channel IDs.
- **ROADMAP.md:** Implements the unchecked `MEMSBridge Android` milestone item.

### Plan Review Issues

All 8 issues from plan-review-1 are correctly addressed in the implementation:

1. `clCNFBCalibrator_ImportIndividualNFBData` with 3 args and error check (`jni_mems.cpp:96-100`). ✅
2. Callback parameter `clCMEMSTimedData memsData` — no `*` (`jni_mems.cpp:32,154`). ✅
3. `noexcept` on callback (`jni_mems.cpp:32,154`). ✅
4. `(uintptr_t)` intermediate cast on all jlong-to-pointer conversions (`jni_mems.cpp:42,54,73,114,137`). ✅
5. Null guard `if (memsHandle == 0) return;` in dispose (`jni_mems.cpp:136`). ✅
6. Null-check before `DeleteGlobalRef` in dispose (`jni_mems.cpp:143-146`). ✅
7. ArrayList JNI mechanics with per-iteration `DeleteLocalRef(sample)` (`jni_mems.cpp:181-201`). ✅
8. No serial extraction in `handleMemsCall` — uses `devBridge.requireHandle()` directly (`NeiryKitPlugin.kt:429`). ✅

### Verification

**JNI layer (`jni_mems.cpp`):**
- Extern declarations match `jni_cardio.cpp` (minus `map_put_bool` — not needed for MEMS).
- `nativeCreateMems` / `nativeCreateMemsCalibrated` mirror cardio equivalents exactly, substituting `clCMEMS_*` for `clCCardio_*`.
- Calibration import uses correct function name, struct field mapping, and error check — verified against `jni_cardio.cpp:95-113`.
- `nativeSetMemsDataSink` null-checks before `DeleteGlobalRef`, matches cardio pattern at `jni_cardio.cpp:142-151`.
- `nativeDisposeMems` has null guard, `(uintptr_t)` cast, callback unregistration, and guarded sink cleanup — matches `jni_cardio.cpp:183-209`.
- Callback threading model correct: `GetEnv`/`AttachCurrentThread`, mutex-guarded `NewLocalRef`, `goto cleanup`, `DetachCurrentThread`.
- Map keys `ax/ay/az/gx/gy/gz/ts` match both iOS `MemsBridge.swift` output and Dart `MemsSample.fromMap()` input exactly.
- Type mapping: `clCPoint3d` float fields → `jfloat` → Java `Float` → Dart `double` (Dart casts via `as num`). Timestamp `int64_t` → `jlong` → Dart `int`. Both correct.
- `DeleteLocalRef(sample)` immediately after `CallBooleanMethod(list, alAdd, sample)` prevents local ref table overflow — matches `jni_device_locator.cpp:75-77`.
- `goto cleanup` correctly skips the `{ }` block; `list` is declared before goto and initialized to `nullptr`, so cleanup handles both paths.

**CMakeLists.txt:** `jni_mems.cpp` added between `jni_cardio.cpp` and `jni_productivity.cpp`. Build file correct.

**NativeBridge.kt:** 4 external function declarations match JNI signatures. Placed in own `// -- MEMS sensor --` section between Cardio and Productivity, following convention.

**MemsBridge.kt:** Structurally identical to `CardioBridge.kt` — inner `MemsStreamHandler`, `allStreamHandlers()`, `create`/`createCalibrated`/`dispose`. Field extraction in `createCalibrated` uses the same `as? Number` safe-cast pattern. `parseSdkError` is accessible as a package-level function from `FlutterError.kt`.

**NeiryKitPlugin.kt:**
- `memsBridge` field, instantiation in `onAttachedToEngine`, stream handler registration, method channel dispatch, and `onDetachedFromEngine` cleanup all follow established patterns.
- `handleMemsCall` mirrors `handleCardioCall` line-for-line (guards, when-dispatch, try/catch).
- Disposal order in `onDetachedFromEngine`: productivity → mems → cardio → ... — classifiers are independent of each other (all depend on device, released last), so order among them is non-critical.

### Critical Issues

None.

### Suggestions

None.

REVIEW_PASS
