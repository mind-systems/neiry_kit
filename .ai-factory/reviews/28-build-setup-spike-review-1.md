## Code Review Summary

**Plan:** `28-build-setup-spike.md`
**Changed files:** 5 (+ 2 binary `.so` files, + 3 `.ai-factory/` doc files)
**Risk Level:** Low

### Verification

- **Channel IDs:** All 8 MethodChannel IDs and 29 EventChannel IDs in `NeiryKitPlugin.kt` verified character-by-character against `lib/src/channel/channel_names.dart`. All match.
- **CMake paths:** `CAPSULE_HEADERS` resolves to `<repo>/official/iOS/CapsuleClient.framework/Headers` — `CCapsuleAPI.h` confirmed present. `CAPSULE_LIBS` resolves to `<repo>/android/src/main/jniLibs/arm64-v8a` — both `.so` files confirmed present.
- **JNI naming:** `Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion` correctly escapes the underscore in `neiry_kit` as `_1`. Matches the `private external fun nativeGetVersion(): String` declaration on `NeiryKitPlugin`.
- **C API:** `clCCapsule_GetVersionString()` declared in `CDeviceLocator.h:32` returns `const char*` — correct input for `env->NewStringUTF()`.
- **Library loading:** `System.loadLibrary("CapsuleClient")` before `System.loadLibrary("neiry_jni")` — correct order per plan review feedback. Ensures `JNI_OnLoad` in `libCapsuleClient.so` fires before any SDK function is called.
- **Duplicate `.so` resolution:** `packaging { jniLibs { pickFirsts } }` present with both `libCapsuleClient.so` and `libc++_shared.so` — resolves the AAR vs `jniLibs/` conflict.
- **CMake linking:** `libc++_shared.so` correctly omitted from `target_link_libraries` — NDK handles C++ runtime linking.
- **`ndkVersion`:** Correctly omitted — AGP picks the default.
- **Plan review issues:** All 2 critical issues and 3 suggestions from `plan-review-1.md` are addressed in the implementation.

### Critical Issues

None.

### Suggestions

1. **Dead `MethodCallHandler` interface and `onMethodCall` override**

   `NeiryKitPlugin` implements `MethodCallHandler` (line 11) and overrides `onMethodCall` (lines 143–145) with `result.notImplemented()`. But this method is never called — each MethodChannel is registered with its own lambda handler in `onAttachedToEngine` (line 41), not with `this`. The interface and override are dead code.

   Not a bug — the dead path returns `notImplemented()` which is safe. But removing `MethodCallHandler` from the class declaration and deleting the `onMethodCall` override would be cleaner. Low priority; can be cleaned up in the next milestone when the bridge classes are introduced.

2. **`StubStreamHandler` declared as `inner class` unnecessarily**

   `private inner class StubStreamHandler` (line 160) holds an implicit reference to the outer `NeiryKitPlugin` instance, but never accesses any outer class members. Could be `private class StubStreamHandler` (nested, not inner) to avoid the implicit reference. No functional impact — the handlers are cleaned up in `onDetachedFromEngine`.

### Positive Notes

- Clean, focused implementation — exactly the scope specified in the plan, nothing more.
- `onDetachedFromEngine` correctly nulls both method handlers and stream handlers, then clears both maps.
- Channel dispatch via `handleMethodCall` + per-domain `handleXxxCall` mirrors the iOS `NeiryKitPlugin.swift` pattern.
- `getVersionString` wired to `device_locator` channel only, matching iOS and the `DeviceLocatorMethods` contract.
- Binary `.so` files are in `jniLibs/arm64-v8a/` — standard Android location, correctly picked up by both CMake (for linking) and Gradle (for APK packaging).

REVIEW_PASS
