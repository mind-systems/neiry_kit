## Code Review Summary

**Plan Reviewed:** `28-build-setup-spike.md`
**Files Referenced:** 8
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge architecture. The Kotlin plugin rewrite mirrors the iOS `NeiryKitPlugin.swift` pattern (per-channel `setMethodCallHandler`, `StubStreamHandler` for unimplemented EventChannels, bridge lookup maps). All 8 MethodChannel IDs and 29 EventChannel IDs match the `channel_names.dart` contract exactly.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** WARN — the roadmap milestone text says "22 EventChannels" but the Dart contract and iOS implementation both have 29. The plan correctly follows the contract (29). Roadmap milestone text is stale.

### Critical Issues

1. **Duplicate native library conflict — build will fail**

   Task 1 extracts `libCapsuleClient.so` and `libc++_shared.so` to `android/src/main/jniLibs/arm64-v8a/`. Task 4 says "Keep the existing `fileTree` AAR dependency — both AARs are still needed at runtime for their Kotlin and resource content."

   `CapsuleService.aar` contains those same `.so` files in its `jni/arm64-v8a/` directory. When Gradle processes the AAR dependency, it extracts `jni/` contents into the APK's `lib/` directory. The manually extracted files in `jniLibs/` also go to the same APK location. This produces:

   ```
   More than one file was found with OS independent path 'lib/arm64-v8a/libCapsuleClient.so'
   ```

   Task 4 must add a `packaging` block to resolve the conflict:

   ```kotlin
   android {
       packaging {
           jniLibs {
               pickFirsts += setOf(
                   "lib/arm64-v8a/libCapsuleClient.so",
                   "lib/arm64-v8a/libc++_shared.so",
               )
           }
       }
   }
   ```

   The extracted `jniLibs/` copies are needed at CMake build time (to link `neiry_jni.so` against `libCapsuleClient.so`); the AAR's copies are redundant at packaging time but the AAR must stay as a dependency because its `classes.jar` contains `com.gelo.capsule.CapsuleNative` which may be needed for SDK initialization.

2. **`CapsuleNative` and `JNI_OnLoad` — SDK initialization may not trigger**

   `CapsuleService.aar` ships `com.gelo.capsule.CapsuleNative` — likely the class the SDK expects consumers to use for JNI initialization. When `CapsuleNative` is loaded by the JVM (via `Class.forName` or a `static` block), it presumably calls `System.loadLibrary("CapsuleClient")`, which triggers `JNI_OnLoad` at address `0xe9207c` inside `libCapsuleClient.so`.

   The plan loads `libCapsuleClient.so` only as a **transitive dependency** of `neiry_jni.so` (via ELF `DT_NEEDED`). The JVM does NOT call `JNI_OnLoad` for transitively loaded libraries — only for libraries explicitly loaded via `System.loadLibrary`. If the SDK's `JNI_OnLoad` performs critical initialization (registering native methods used by `CapsuleNative`, initializing global state), the plan's approach may cause `clCCapsule_GetVersionString()` to crash or return garbage.

   Add an explicit `System.loadLibrary("CapsuleClient")` in the companion object, **before** `System.loadLibrary("neiry_jni")`:

   ```kotlin
   companion object {
       init {
           System.loadLibrary("CapsuleClient")  // triggers JNI_OnLoad in SDK
           System.loadLibrary("neiry_jni")
       }
   }
   ```

   If the spike proves `JNI_OnLoad` is not needed (i.e., `getVersionString` works without it), remove the extra load and document why. But the plan should include this as the default safe path, not omit it.

### Suggestions

1. **`external fun` placement — future refactoring cost**

   The plan puts `private external fun nativeGetVersion(): String` directly on `NeiryKitPlugin`. The explore note (`11-explore-android-jni.md`) recommends a separate `NativeBridge` class where all `external fun` declarations live, because future milestones will add 30+ JNI functions and mixing them into the plugin class creates a maintenance problem.

   More importantly, the JNI function name includes the class name: `Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion`. When this moves to `NativeBridge`, every JNI C function must be renamed to `Java_com_neiry_neiry_1kit_NativeBridge_*`. For a single spike function this is trivial, but the plan should add a note: "The `external fun` is on `NeiryKitPlugin` for this spike. The DeviceLocatorBridge milestone will introduce `NativeBridge` as a separate class and this function will move there."

2. **Task 4 — `ndkVersion` should not hardcode a version**

   The plan says to set `ndkVersion` to e.g. `"27.0.12077973"` but hedges with "check `ANDROID_HOME/ndk/`". This is underspecified — the implementer might pick a version that doesn't exist on CI, or the version string might be wrong. Better: set `ndkVersion` to the version that Flutter's Gradle plugin requires (check `example/android/build.gradle.kts` or Flutter docs), or omit it entirely and let the AGP pick the default NDK from the SDK.

3. **Explicit `libc++_shared.so` link is non-standard**

   Task 2's CMakeLists.txt explicitly links `neiry_jni` against `${CAPSULE_LIBS}/libc++_shared.so`. The Android NDK toolchain already handles C++ runtime linking — the `ANDROID_STL` variable defaults to `c++_shared` since NDK r18+. Explicitly linking a specific copy can cause version mismatches if the NDK's bundled `libc++_shared.so` differs from the one extracted from the AAR.

   Safer approach: remove `libc++_shared.so` from `target_link_libraries` and let the NDK handle it. The extracted copy in `jniLibs/` is still needed for APK packaging (so the runtime can find it), but CMake shouldn't link against it directly.

### Positive Notes

- All 8 MethodChannel IDs and 29 EventChannel IDs in Task 5 match `NeiryChannels` and `NeiryEvents` in `channel_names.dart` character-for-character, and match the iOS `NeiryKitPlugin.swift` implementation exactly.
- The `_1` JNI naming escape for the underscore in `neiry_kit` is correctly identified and applied.
- Correctly avoids defining `JNI_OnLoad` in `jni_bridge.cpp` — each `.so` can only have one, and `libCapsuleClient.so` already defines it.
- Correctly identifies `devicedriver.aar` as pure Kotlin (confirmed: no `jni/` directory) and `CapsuleService.aar` as the source of native binaries.
- The CMake header path (`${CMAKE_CURRENT_SOURCE_DIR}/../../../../official/iOS/CapsuleClient.framework/Headers`) correctly resolves to `<repo>/official/iOS/CapsuleClient.framework/Headers` — verified that `CCapsuleAPI.h` exists there and includes all 17 C headers.
- The example app already has a direct `MethodChannel('neiry_kit/device_locator').invokeMethod('getVersionString')` call from the iOS spike — no Dart-side changes needed to exercise the Android bridge.
- The `StubStreamHandler` pattern (no-op `onListen`/`onCancel`) matches the iOS implementation and is the correct approach for unimplemented channels.
- Clean two-commit plan: native extraction + CMake first, then Gradle + Kotlin plugin. Each commit is independently buildable.
