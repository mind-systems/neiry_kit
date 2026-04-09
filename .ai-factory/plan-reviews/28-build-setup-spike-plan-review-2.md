## Code Review Summary

**Plan Reviewed:** `28-build-setup-spike.md`
**Files Referenced:** 8
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge architecture. Kotlin plugin rewrite mirrors the iOS `NeiryKitPlugin.swift` pattern (per-channel dispatch, `StubStreamHandler` for unimplemented EventChannels, map-based channel storage). All 8 MethodChannel IDs and 29 EventChannel IDs match the `channel_names.dart` contract and the iOS implementation.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** WARN — milestone text says "22 EventChannels" but the Dart contract and iOS implementation both have 29. The plan correctly targets 29. Stale roadmap text, not a plan defect.

### Critical Issues

None. All critical issues from review-1 have been addressed:

- **Duplicate `.so` conflict:** Task 4 now includes the `packaging { jniLibs { pickFirsts } }` block to resolve the conflict between manually extracted `jniLibs/` files and the AAR's embedded copies.
- **`JNI_OnLoad` initialization:** Task 5 now includes explicit `System.loadLibrary("CapsuleClient")` before `System.loadLibrary("neiry_jni")` in the companion object, with a pragmatic note to remove it if the spike proves it unnecessary.
- **`libc++_shared.so` linking:** Task 2 now explicitly says NOT to link it in CMake, letting the NDK handle C++ runtime linking automatically.
- **`ndkVersion` hardcoding:** Task 4 now says NOT to set `ndkVersion`, letting AGP pick the default.
- **`external fun` placement:** Task 3 now documents the spike-only placement on `NeiryKitPlugin` and notes the planned move to `NativeBridge` in the DeviceLocatorBridge milestone.

### Suggestions

None.

### Positive Notes

- All 29 EventChannel IDs and 8 MethodChannel IDs verified character-for-character against `lib/src/channel/channel_names.dart` and `ios/Classes/NeiryKitPlugin.swift`.
- CMake header path (`${CMAKE_CURRENT_SOURCE_DIR}/../../../../official/iOS/CapsuleClient.framework/Headers`) correctly resolves to `<repo>/official/iOS/CapsuleClient.framework/Headers/` — verified `CCapsuleAPI.h` exists there.
- CMake lib path (`${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a`) correctly resolves to the extraction target from Task 1.
- `_1` JNI naming escape for the underscore in `neiry_kit` is correctly applied in the JNI function signature.
- The `getVersionString` spike is correctly wired to the `device_locator` MethodChannel, matching the iOS implementation and `DeviceLocatorMethods.getVersionString` constant.
- Library loading order (CapsuleClient → neiry_jni) correctly ensures the SDK's `JNI_OnLoad` fires before the JNI bridge tries to call SDK functions.
- Two-commit plan is clean: Commit 1 (native extraction + CMake) and Commit 2 (Gradle + Kotlin plugin) are each independently buildable checkpoints.
- `.gitignore` verified — no rules exclude `.so` files from `android/src/main/jniLibs/`, so the extracted binaries will be tracked correctly.
- `devicedriver.aar` correctly identified as pure Kotlin (no `jni/` directory) — no extraction needed.

PLAN_REVIEW_PASS
