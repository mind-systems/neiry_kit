# Plan: Android build setup + spike

## Context

Set up the Android NDK/JNI build pipeline and verify that the plugin can call into the native C SDK. This is the foundation for all subsequent Android bridge milestones — extract the `.so` from the AAR, wire up CMake, write a minimal JNI stub that calls `clCCapsule_GetVersionString()`, and register all MethodChannel + EventChannel stubs mirroring the iOS plugin structure.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Native library extraction and CMake

- [x] **Task 1: Extract `.so` files from `CapsuleService.aar`**
  Files: `android/src/main/jniLibs/arm64-v8a/libCapsuleClient.so`, `android/src/main/jniLibs/arm64-v8a/libc++_shared.so`
  Unzip `official/Android/CapsuleService.aar` and copy `jni/arm64-v8a/libCapsuleClient.so` and `jni/arm64-v8a/libc++_shared.so` into `android/src/main/jniLibs/arm64-v8a/`. These are the pre-built native binaries the JNI bridge will link against at CMake build time. `devicedriver.aar` is pure Kotlin — no extraction needed. Only arm64-v8a is supported (no simulator ABI). Note: `CapsuleService.aar` also ships these same `.so` files inside its `jni/` directory, which Gradle will extract into the APK. The duplicate is resolved in Task 4 via `pickFirsts`.

- [x] **Task 2: Create `CMakeLists.txt` for `neiry_jni` shared library**
  Files: `android/src/main/cpp/CMakeLists.txt`
  Create `android/src/main/cpp/CMakeLists.txt` with `cmake_minimum_required(VERSION 3.18)`. Define `neiry_jni` as a `SHARED` library with `jni_bridge.cpp` as source. Set `CAPSULE_LIBS` to `${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a` and `CAPSULE_HEADERS` to `${CMAKE_CURRENT_SOURCE_DIR}/../../../../official/iOS/CapsuleClient.framework/Headers` (same C headers for both platforms). Add `target_include_directories(neiry_jni PRIVATE ${CAPSULE_HEADERS})`. Link against `${CAPSULE_LIBS}/libCapsuleClient.so`, `android`, and `log`. Do NOT explicitly link `libc++_shared.so` — the NDK toolchain handles C++ runtime linking automatically via `ANDROID_STL` (defaults to `c++_shared` since NDK r18+). Explicitly linking the AAR's extracted copy can cause version mismatches with the NDK's bundled copy. Follow the pattern from `.ai-factory/notes/11-explore-android-jni.md`.

- [x] **Task 3: Create `jni_bridge.cpp` with `nativeGetVersion()` spike** (depends on Task 2)
  Files: `android/src/main/cpp/jni_bridge.cpp`
  Create the JNI entry point file. Include `<jni.h>` and `"CCapsuleAPI.h"`. Implement a single function:
  ```c
  extern "C" JNIEXPORT jstring JNICALL
  Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion(JNIEnv* env, jobject) {
      return env->NewStringUTF(clCCapsule_GetVersionString());
  }
  ```
  Use `Java_com_neiry_neiry_1kit_` prefix (note `_1` for the underscore in `neiry_kit`). Do NOT define `JNI_OnLoad` — `libCapsuleClient.so` already defines one and only one can be active per `.so`. Note: the `external fun` is placed on `NeiryKitPlugin` for this spike only. The DeviceLocatorBridge milestone will introduce a separate `NativeBridge` class where all `external fun` declarations will live, and this function will move there. For a single spike function the JNI rename is trivial.

### Phase 2: Gradle configuration

- [x] **Task 4: Add `externalNativeBuild` and NDK config to `build.gradle.kts`** (depends on Task 2)
  Files: `android/build.gradle.kts`
  Inside the `android { }` block add:
  - Do NOT set `ndkVersion` — let AGP pick the default NDK from the SDK. This avoids hardcoding a version that may not exist on CI or other developer machines.
  - Inside `defaultConfig { }` add `ndk { abiFilters += "arm64-v8a" }` to restrict to the single supported ABI and `externalNativeBuild { cmake { cppFlags += "" } }`.
  - At the `android { }` level add `externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }`.
  - Add a `packaging` block to resolve the duplicate `.so` conflict between the manually extracted `jniLibs/` files (needed at CMake link time) and the identical copies that Gradle extracts from `CapsuleService.aar` into the APK:
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
    Without this, the build fails with `More than one file was found with OS independent path 'lib/arm64-v8a/libCapsuleClient.so'`.
  - Keep the existing `fileTree` AAR dependency — both AARs are still needed at runtime for their Kotlin and resource content (`CapsuleService.aar` contains `com.gelo.capsule.CapsuleNative` which may be needed for SDK initialization). Do not remove or change any other existing config.

### Phase 3: Kotlin plugin rewrite

- [x] **Task 5: Rewrite `NeiryKitPlugin.kt` — load libraries, declare `external fun`, register all channels**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  Completely rewrite the current scaffold. The new plugin must:

  **Library loading:** Add a `companion object { init { ... } }` block that loads both native libraries in the correct order:
  ```kotlin
  companion object {
      init {
          System.loadLibrary("CapsuleClient")  // triggers JNI_OnLoad in SDK
          System.loadLibrary("neiry_jni")
      }
  }
  ```
  `CapsuleClient` must be loaded explicitly and first — the JVM does NOT call `JNI_OnLoad` for transitively loaded libraries (i.e., libraries loaded only as ELF `DT_NEEDED` dependencies of `neiry_jni`). If the SDK's `JNI_OnLoad` performs critical initialization (registering native methods, initializing global state), skipping it would cause `clCCapsule_GetVersionString()` to crash or return garbage. If the spike proves `JNI_OnLoad` is not needed (i.e., `getVersionString` works without the explicit load), remove the extra load and document why.

  **JNI spike:** Declare `private external fun nativeGetVersion(): String`. Wire it into the `device_locator` MethodChannel handler under method name `"getVersionString"` — call `nativeGetVersion()` and return the result. This verifies the full chain: Dart → MethodChannel → Kotlin → JNI → C SDK → back.

  **MethodChannel registration (8 channels):** Register all 8 channels matching the iOS plugin exactly. Channel IDs (from `lib/src/channel/channel_names.dart`):
  - `neiry_kit/device_locator`
  - `neiry_kit/device`
  - `neiry_kit/nfb`
  - `neiry_kit/physiological`
  - `neiry_kit/emotions`
  - `neiry_kit/productivity`
  - `neiry_kit/cardio`
  - `neiry_kit/nfb_calibrator`

  Each channel gets a `setMethodCallHandler` that dispatches to a dedicated `handleXxxCall` private method based on `channelId` (same `if/else if` pattern as iOS `NeiryKitPlugin.swift`). Only `device_locator` channel has the real `"getVersionString"` handler; all other method handlers return `result.notImplemented()` for now.

  **EventChannel registration (29 channels):** Register all 29 EventChannels with `StubStreamHandler` (a private inner class where `onListen` and `onCancel` both return null and do nothing — same pattern as iOS `StubStreamHandler`). Channel IDs:
  - `neiry_kit/events/deviceList`
  - `neiry_kit/events/eeg`
  - `neiry_kit/events/psd`
  - `neiry_kit/events/eegArtifacts`
  - `neiry_kit/events/resistance`
  - `neiry_kit/events/battery`
  - `neiry_kit/events/connectionStatus`
  - `neiry_kit/events/modeSwitched`
  - `neiry_kit/events/nfbState`
  - `neiry_kit/events/physiologicalState`
  - `neiry_kit/events/emotionsState`
  - `neiry_kit/events/productivityMetrics`
  - `neiry_kit/events/productivityIndexes`
  - `neiry_kit/events/cardioData`
  - `neiry_kit/events/ppgData`
  - `neiry_kit/events/memsData`
  - `neiry_kit/events/nfbCalibration`
  - `neiry_kit/events/physiologicalCalibrationProgress`
  - `neiry_kit/events/physiologicalCalibrated`
  - `neiry_kit/events/physiologicalIndividualNfb`
  - `neiry_kit/events/productivityCalibrationProgress`
  - `neiry_kit/events/productivityCalibrated`
  - `neiry_kit/events/productivityBaselines`
  - `neiry_kit/events/productivityIndividualNfb`
  - `neiry_kit/events/cardioCalibratedEvent`
  - `neiry_kit/events/error`
  - `neiry_kit/events/nfbError`
  - `neiry_kit/events/emotionsError`
  - `neiry_kit/events/productivityError`

  **Cleanup:** `onDetachedFromEngine` must call `setMethodCallHandler(null)` on all MethodChannels and `setStreamHandler(null)` on all EventChannels, then clear the stored references. Store channels in `Map<String, MethodChannel>` and `Map<String, EventChannel>` (same pattern as iOS).

  Mirror the iOS `NeiryKitPlugin.swift` structure closely — the Dart side expects identical channel names and identical `notImplemented()` responses for unimplemented methods across both platforms.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Extract native .so from AAR and add CMake build for neiry_jni"
- **Commit 2** (after tasks 4-5): "Wire Gradle NDK build and rewrite NeiryKitPlugin with all channel stubs"
