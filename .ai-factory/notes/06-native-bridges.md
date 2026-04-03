# Native Bridges — iOS and Android

**Date:** 2026-04-03
**Source:** SDK docs — get_started, capsule_flow, example; existing plugin files; official/iOS and official/Android inspection

## Key Findings

- iOS: `CapsuleClient.framework` linked via `vendored_frameworks` in podspec; headers already in framework's `Headers/` directory
- Android: both AARs linked via `fileTree` in build.gradle.kts — no JNI setup needed, AAR wraps C internally
- SDK callbacks fire on background thread by default — MUST dispatch to main thread before calling `eventSink.success()`
- Use `[weak self]` in ALL Swift C callbacks to avoid retain cycles with C closures
- License key required (v1.4.0+) for classifier outputs — raw signal streaming works without key
- Both current plugin stubs (iOS Swift, Android Kotlin) are pure boilerplate — no SDK linking yet

## Details

### iOS podspec changes needed

```ruby
s.vendored_frameworks = '../official/iOS/CapsuleClient.framework'

s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/../.symlinks/plugins/neiry_kit/ios/../official/iOS/CapsuleClient.framework/Headers"'
}
```

Framework is arm64-only, iOS 13.0+. No Objective-C bridging header needed — use direct C import.

### Android build.gradle.kts — already mostly correct

```kotlin
dependencies {
    implementation(fileTree(mapOf("dir" to "../official/Android", "include" to listOf("*.aar"))))
}
```

Both `CapsuleService.aar` and `devicedriver.aar` must be present. No CMake or externalNativeBuild needed.

ProGuard: if enabled, add `-keep class com.neiry.** { *; }`

### Thread-safe EventChannel pattern

**Swift:**
```swift
clCDevice_SetOnEEGDataEvent(device) { [weak self] _, data in
    guard let self, let sink = self.eegSink else { return }
    let map: [String: Any] = ["ts": data.timestampMilli, ...]
    DispatchQueue.main.async { sink(map) }
}
```

**Kotlin:**
```kotlin
setOnEEGDataEvent(device) { data ->
    val map = mapOf("ts" to data.timestampMilli, ...)
    Handler(Looper.getMainLooper()).post {
        eventSink?.success(map)
    }
}
```

Rule: never call `sink.success()` / `events.success()` from a C callback thread.

### OpaquePointer lifecycle (Swift)

```swift
class DeviceLocatorBridge {
    private var locator: OpaquePointer?

    func create() throws {
        var error = clCError()
        locator = clCDeviceLocator_Create(&error)
        if error.hasError { throw NeiryException(error) }
    }

    deinit {
        if let locator { clCDeviceLocator_Destroy(locator) }
    }
}
```

- Store as `OpaquePointer?`, null-check before use, destroy in `deinit`
- Kotlin equivalent: `Long` (JNI opaque handle)

### FlutterPlugin registration pattern

In `NeiryKitPlugin.swift register(with:)`:
1. Create all MethodChannels and EventChannels upfront
2. `addMethodCallDelegate(instance, channel:)` for each MethodChannel
3. `setStreamHandler(bridge)` for each EventChannel
4. Each bridge class implements `FlutterStreamHandler` independently

### Known gotchas

| Issue | Platform | Fix |
|---|---|---|
| Code signing prompt on first run | iOS | Expected, allow Xcode ad-hoc signing |
| Main thread dispatch easy to forget | Android | Always wrap `eventSink?.success()` in `Handler(Looper.getMainLooper()).post{}` |
| Simulator support | iOS | Framework is arm64-only; run on real device |
| ProGuard obfuscation | Android | Keep `com.neiry.**` classes |
| License key for classifiers | Both | Expose `clCLicenseManager` in Dart API |
| Screen sleep during calibration | Both | iOS: `isIdleTimerDisabled`; Android: wake lock |

### Platform comparison table

| Aspect | iOS | Android |
|---|---|---|
| SDK artifact | `CapsuleClient.framework` | `CapsuleService.aar` + `devicedriver.aar` |
| Build config | podspec `vendored_frameworks` | Gradle `fileTree` |
| Callback thread | Background (BLE queue) | JNI worker thread |
| Main thread dispatch | `DispatchQueue.main.async` | `Handler(Looper.getMainLooper()).post` |
| Opaque handle type | `OpaquePointer` | `Long` |
| Cleanup | `deinit` → `*_Destroy()` | `onCancel()` → cleanup |
| Min target | iOS 13.0 | Android 10 (minSdk 24) |

### iOS: Swift import of C headers (resolved)

`CapsuleClient.framework` has no `Modules/module.modulemap` → `import CapsuleClient` does NOT work. It's a plain C/C++ library with no Swift module.

**Correct approach — Objective-C umbrella header:**

1. Create `ios/Classes/NeiryKitBridge.h`:
```objc
#ifndef NeiryKitBridge_h
#define NeiryKitBridge_h
#include "CCapsuleAPI.h"
#endif
```

2. Add to podspec:
```ruby
s.public_header_files = 'Classes/**/*.h'
```

In Swift files all C functions are then available as globals (`clCDeviceLocator_Create()` etc.) — no import statement needed. This is the standard Flutter iOS plugin pattern for vendored C frameworks.

**Spike (fold into bridge setup commit):** Add `clCCapsule_GetVersionString()` call in `NeiryKitPlugin.swift` to confirm compilation before writing any bridges.

### Android: JNI approach (resolved)

`libCapsuleClient.so` exports all `clC*` functions as plain C symbols (not mangled, not hidden). No thick C++ wrapper needed — just a thin JNI marshaling layer.

**Loading:** `CapsuleNative.initCapsule()` calls `System.loadLibrary("CapsuleClient")` — call this in `onAttachedToEngine`, no additional load needed.

**`.so` placement:** symlink or copy `official/Android/CapsuleService.aar`'s `jni/arm64-v8a/libCapsuleClient.so` to `android/src/main/jniLibs/arm64-v8a/`.

**Headers:** reuse `official/iOS/CapsuleClient.framework/Headers/` — same C API for both platforms.

**Platform comparison (complete):**

| Aspect | iOS | Android |
|---|---|---|
| SDK loading | automatic (framework) | `CapsuleNative.initCapsule()` in `onAttachedToEngine` |
| Pointer type | `OpaquePointer` in Swift | `jlong` (`Long`) in Kotlin |
| Callbacks | `DispatchQueue.main.async` | `Handler(Looper.getMainLooper()).post` |
| Marshaling | none — Swift sees C directly | thin `.cpp` file with JNI (`RegisterNatives` or `Java_...`) |
| Headers | from framework | same `official/iOS/.../Headers/` |

**Spike pattern (fold into bridge setup commit):**

```cpp
// android/src/main/cpp/jni_bridge.cpp
#include "CCapsuleAPI.h"
extern "C" JNIEXPORT jstring JNICALL
Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion(JNIEnv* env, jobject) {
    return env->NewStringUTF(clCCapsule_GetVersionString());
}
```

```cmake
# android/src/main/cpp/CMakeLists.txt
add_library(neiry_jni SHARED jni_bridge.cpp)
target_include_directories(neiry_jni PRIVATE
    ../../../../official/iOS/CapsuleClient.framework/Headers)
target_link_libraries(neiry_jni
    ${CMAKE_SOURCE_DIR}/../jniLibs/arm64-v8a/libCapsuleClient.so)
```

### NfbCalibratorBridge — single EventChannel, sealed event protocol

Both platforms emit all calibration events over **one** EventChannel (`neiry_kit/events/nfbCalibration`). The native side maps two SDK callbacks to one channel using a `type` key; the Dart side deserializes the map into the correct `CalibrationEvent` subtype.

**SDK callbacks → channel events:**

| SDK callback | Emitted map |
|---|---|
| `SetOnIndividualNFBStageFinishedEvent` | `{'type': 'stage', 'stage': <1..4>}` |
| `SetOnIndividualNFBCalibratedEvent` | `{'type': 'done', 'data': <IndividualNfbData map>}` |

**Swift:**
```swift
clCNFBCalibrator_SetOnIndividualNFBStageFinishedEvent(calibrator) { [weak self] _, stage in
    guard let sink = self?.calibrationSink else { return }
    DispatchQueue.main.async {
        sink(["type": "stage", "stage": Int(stage)])
    }
}

clCNFBCalibrator_SetOnIndividualNFBCalibratedEvent(calibrator) { [weak self] _, data in
    guard let sink = self?.calibrationSink else { return }
    let map: [String: Any] = [
        "type": "done",
        "data": [
            "ts": data.timestamp,
            "failReason": Int(data.failReason.rawValue),
            "individualFrequency": data.individualFrequency,
            "individualPeakFrequencyPower": data.individualPeakFrequencyPower,
            "individualPeakFrequencySuppression": data.individualPeakFrequencySuppression,
            "individualBandwidth": data.individualBandwidth,
            "individualNormalizedPower": data.individualNormalizedPower,
            "lowerFrequency": data.lowerFrequency,
            "upperFrequency": data.upperFrequency,
        ]
    ]
    DispatchQueue.main.async { sink(map) }
}
```

**Kotlin:**
```kotlin
setOnIndividualNFBStageFinishedEvent(calibrator) { stage ->
    Handler(Looper.getMainLooper()).post {
        eventSink?.success(mapOf("type" to "stage", "stage" to stage.value))
    }
}

setOnIndividualNFBCalibratedEvent(calibrator) { data ->
    val map = mapOf(
        "type" to "done",
        "data" to mapOf(
            "ts" to data.timestamp,
            "failReason" to data.failReason.value,
            "individualFrequency" to data.individualFrequency,
            "individualPeakFrequencyPower" to data.individualPeakFrequencyPower,
            "individualPeakFrequencySuppression" to data.individualPeakFrequencySuppression,
            "individualBandwidth" to data.individualBandwidth,
            "individualNormalizedPower" to data.individualNormalizedPower,
            "lowerFrequency" to data.lowerFrequency,
            "upperFrequency" to data.upperFrequency,
        )
    )
    Handler(Looper.getMainLooper()).post { eventSink?.success(map) }
}
```

Both bridges store a single `calibrationSink` / `eventSink` reference set in `onListen`, cleared in `onCancel`. The `startCalibration` MethodChannel call starts the SDK process; the EventChannel subscription is independent — subscribe before calling `startCalibration`.

## Open Questions

- License key provisioning flow — where/how the key is embedded in the app
