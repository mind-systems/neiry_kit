# Explore: Android Build Setup — AAR Structure & JNI Path

Research findings before implementing the Android `build setup + spike` milestone.

## The core question: is the ROADMAP correct?

**ROADMAP says:** copy `libCapsuleClient.so` to `jniLibs/arm64-v8a/`, add `CMakeLists.txt` + `externalNativeBuild`.

**Short answer:** Partially. The `.so` lives inside `CapsuleService.aar`. Two valid paths exist; the ROADMAP conflates both.

## AAR structure

Both `CapsuleService.aar` (4.4 MB) and `devicedriver.aar` (158 KB) are ZIP archives. Per `06-native-bridges.md` line 147, the native library lives at:

```
CapsuleService.aar
└── jni/
    └── arm64-v8a/
        └── libCapsuleClient.so   ← this is the library
```

`devicedriver.aar` is likely a BLE hardware abstraction layer — a separate native component that must also be present.

## Two divergent paths in 06-native-bridges.md

The spec has an **internal contradiction** — two approaches described in the same file:

### Path A — Gradle-only (lines 9, 39)
> "Android: both AARs linked via `fileTree` in build.gradle.kts — no JNI setup needed, AAR wraps C internally"
> "Both CapsuleService.aar and devicedriver.aar must be present. No CMake or externalNativeBuild needed."

- Keep existing `fileTree` dependency in `build.gradle.kts`
- No `.so` extraction, no `CMakeLists.txt`, no `externalNativeBuild`
- The AAR provides the native layer; Kotlin calls through it
- **Unclear:** how Kotlin accesses the C symbols without a JNI shim

### Path B — Custom JNI wrapper (lines 141–179, spike code)
> "symlink or copy `official/Android/CapsuleService.aar`'s `jni/arm64-v8a/libCapsuleClient.so` to `android/src/main/jniLibs/arm64-v8a/`"

- Extract `libCapsuleClient.so` from AAR into `android/src/main/jniLibs/arm64-v8a/`
- Write `android/src/main/cpp/jni_bridge.cpp` with C JNI stubs
- Add `CMakeLists.txt` that builds `neiry_jni` shared lib linking against the extracted `.so`
- Add `externalNativeBuild` block to `build.gradle.kts` pointing to `CMakeLists.txt`
- Add `external fun` declarations to `NeiryKitPlugin.kt`
- Load via `System.loadLibrary("neiry_jni")` → calls `nativeGetVersion()` as spike

**The spike verification pattern (line ~163) strongly implies Path B is intended.**

## Current state of android/build.gradle.kts

The existing file uses Path A only:
```kotlin
implementation(fileTree(mapOf("dir" to "../official/Android", "include" to listOf("*.aar"))))
```
No `externalNativeBuild`, no `.so` copy. This is incomplete for Path B.

## CMakeLists.txt shape (if Path B)

Per spec lines 173–179:
```cmake
add_library(neiry_jni SHARED jni_bridge.cpp)
target_include_directories(neiry_jni PRIVATE
    ../../../../official/iOS/CapsuleClient.framework/Headers)
target_link_libraries(neiry_jni
    ${CMAKE_SOURCE_DIR}/../jniLibs/arm64-v8a/libCapsuleClient.so)
```

Note: iOS headers are reused for Android — both platforms share the same C API.

## JNI naming convention

Spike function maps to:
```cpp
Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion(JNIEnv* env, jobject)
```

Package: `com.neiry.neiry_kit` — matches existing `build.gradle.kts` namespace. Class: `NeiryKitPlugin`.

## AAR contents (verified)

```
CapsuleService.aar
├── classes.jar          (3.7 KB — thin Java/Kotlin wrapper)
└── jni/
    └── arm64-v8a/
        ├── libCapsuleClient.so   (21.7 MB — the C SDK)
        └── libc++_shared.so      (1.2 MB — C++ stdlib)

devicedriver.aar
└── classes.jar          (141 KB — BLE driver, pure Java/Kotlin, no .so)
```

**Conclusions:**
1. **arm64-v8a only** — no x86_64 or armeabi-v7a. Simulator testing on Android not possible.
2. `devicedriver.aar` has **no native library** — pure Java/Kotlin BLE driver, no extraction needed.
3. `CapsuleService.aar` contains `libCapsuleClient.so` + `libc++_shared.so`. Both must be present at runtime.
4. `classes.jar` in `CapsuleService.aar` is tiny (3.7 KB) — likely just a loader stub, not a full API surface.

## Decision: Path B is correct

`devicedriver.aar` is self-contained (pure Kotlin). `CapsuleService.aar` bundles the `.so` but the `classes.jar` is too small to expose the full C API — it's a stub. The Kotlin bridge must call C functions directly via JNI, which requires Path B.

**Correct setup for the spike:**
1. Extract from `CapsuleService.aar`: copy `jni/arm64-v8a/libCapsuleClient.so` and `jni/arm64-v8a/libc++_shared.so` to `android/src/main/jniLibs/arm64-v8a/`
2. Keep `fileTree` dependency for both AARs (needed for `devicedriver` and the `classes.jar` stub)
3. Add `CMakeLists.txt` building `neiry_jni` shared lib, linking against the extracted `.so`
4. Add `externalNativeBuild` block to `build.gradle.kts`
5. Add `external fun nativeGetVersion(): String` to `NeiryKitPlugin.kt`

**Note:** `libc++_shared.so` must also be copied alongside `libCapsuleClient.so` — it's a runtime dependency of the SDK.
