## Code Review Summary

**Plan Reviewed:** `.ai-factory/plans/47-memsbridge-android.md`
**Files Analyzed:** 12 (plan + 11 codebase reference files)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** No issues. Plan follows "one bridge class per C API module" and "platform bridges must never cross-call each other" rules. MEMS bridge gets its own JNI file, Kotlin class, and channel IDs.
- **RULES.md:** WARN — file does not exist.
- **ROADMAP.md:** No issues. This plan implements the single unchecked item under "MEMS classifier" — `MEMSBridge Android`. Scope matches the milestone description exactly.

### Previous Review Issues

All 8 issues from plan-review-1 have been addressed:

1. C API function name corrected to `clCNFBCalibrator_ImportIndividualNFBData` with `clCError*` third parameter (Task 1, step 2).
2. Callback parameter type corrected to `clCMEMSTimedData memsData` (no `*`).
3. `noexcept` added to callback signature.
4. `(uintptr_t)` intermediate cast specified on all `jlong`-to-pointer conversions.
5. Null guard `if (memsHandle == 0) return;` added to `nativeDisposeMems`.
6. Null-check on `g_memsDataSink` before `DeleteGlobalRef` added with explicit code block.
7. ArrayList JNI construction pattern fully specified with `FindClass`/`GetMethodID`/`NewObject` and per-iteration `DeleteLocalRef(sample)`.
8. Serial extraction removed from `handleMemsCall` `"create"` branch — plan explicitly notes this is not needed.

### Critical Issues

None.

### Verification Against Codebase

**JNI layer (`jni_mems.cpp`):**
- Extern declarations match `jni_cardio.cpp` pattern — globals from `jni_device_locator.cpp`, map helpers from `jni_device.cpp`, error helper.
- `clCMEMS_Create` / `clCMEMS_CreateCalibrated` / `clCMEMS_SetOnMEMSTimedDataUpdateEvent` signatures match iOS `MemsBridge.swift` usage.
- Callback data accessors (`GetCount`, `GetAccelerometer`, `GetGyroscope`, `GetTimestampMilli`) correctly specified as no-`clCError*`, while `SetOnMEMSTimedDataUpdateEvent` correctly takes `clCError*`.
- Map keys (`ax/ay/az/gx/gy/gz/ts`) match `MemsSample.fromMap()` exactly.
- `clCPoint3d` fields accessed as `.x/.y/.z` with `map_put_float` — correct type (C `float` maps to Java `Float` maps to Dart `double` via standard message codec).
- Timestamp as `jlong` via `map_put_long` — correct (`int64_t` maps to Dart `int`).
- Thread safety: `pthread_mutex_t` guarding sink, `NewLocalRef` under lock, `goto cleanup`, `DetachCurrentThread` on all return paths. All match the established pattern.

**CMakeLists.txt (Task 2):** Adding `jni_mems.cpp` after `jni_productivity.cpp` — correct position, file exists at the specified path.

**NativeBridge.kt (Task 3):** 4 function signatures match the JNI implementations. `EventChannel.EventSink?` nullable parameter for `nativeSetMemsDataSink` matches the cardio pattern. Section header comment convention (`// -- MEMS sensor --`) matches existing sections.

**MemsBridge.kt (Task 4):** Structure mirrors `CardioBridge.kt` exactly — inner stream handler, `allStreamHandlers()`, `create`/`createCalibrated`/`dispose`, try/catch with `parseSdkError`. EventChannel ID `"neiry_kit/events/memsData"` matches `NeiryEvents.memsData` in `channel_names.dart:43`.

**NeiryKitPlugin.kt (Task 5):**
- `"neiry_kit/mems"` matches `NeiryChannels.mems` in `channel_names.dart:18`.
- `"neiry_kit/events/memsData"` already registered at line 103 with `StubStreamHandler` — plan correctly wires the real handler to replace it via the `streamHandlerMap` build block.
- `handleMemsCall` dispatch mirrors `handleCardioCall` (lines 384-411): guard both `memsBridge` and `deviceBridge`, use `devBridge.requireHandle()`, extract `calibrationData` from args.
- `onDetachedFromEngine` disposal — plan leaves exact position open but references reverse-order convention. Since classifier bridges are independent of each other (all depend only on device, released last), the position among classifiers is not critical.

### Positive Notes

- All 8 issues from the first review are resolved with precision — each fix references the exact codebase line and pattern.
- The plan is implementation-ready: every JNI function signature, Kotlin declaration, and plugin wiring step is specified with enough detail to code directly from the plan without ambiguity.
- iOS parity is complete: same factory paths (plain + calibrated), same `allStreamHandlers()` pattern, same dispose semantics, same callback data serialization format.
- The two-commit strategy cleanly separates native (JNI + CMake) from Kotlin (bridge + plugin wiring), allowing independent verification of the C build before layering Kotlin on top.

PLAN_REVIEW_PASS
