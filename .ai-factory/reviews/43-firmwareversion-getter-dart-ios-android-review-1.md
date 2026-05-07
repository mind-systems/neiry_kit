## Code Review: firmwareVersion getter — Dart + iOS + Android

**Files reviewed:**
- `lib/src/channel/channel_names.dart` (line 103)
- `lib/src/api/device.dart` (lines 404–413)
- `ios/Classes/DeviceBridge.swift` (lines 509–518)
- `ios/Classes/NeiryKitPlugin.swift` (lines 307–315)
- `android/src/main/cpp/jni_device.cpp` (lines 358–370)
- `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt` (line 55)
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt` (lines 244–251)
- `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt` (line 225)

### Method name consistency

Dart constant `'getFirmwareVersion'`, iOS switch case `"getFirmwareVersion"`, Android when case `"getFirmwareVersion"` — all three match exactly.

### Dart layer

`getFirmwareVersion()` guards with `_checkNotDisposed()` + `_checkConnected()`, uses `invokeMethod<String>`, returns `result!`. Identical pattern to `getChannelName()` (line 383). Correct.

### iOS layer

`DeviceBridge.getFirmwareVersion()` follows `getEEGSampleRate()` pattern with an additional nil-guard on the `const char*` return — consistent with `getChannelNameByIndex()` (line 559) which also nil-guards C string pointers. `String(cString:)` copies the bytes — no memory ownership issue. Dispatch case in `NeiryKitPlugin.swift` uses the standard do/catch pattern.

### Android JNI layer

`nativeGetFirmwareVersion` returns `jstring` via `NewStringUTF(result ? result : "")`. The null-guard prevents passing nullptr to JNI if the SDK returns null on success (defensive). Error path calls `throw_sdk_error` + returns nullptr — matches existing getters like `nativeGetChannelNames` (line 383). The thrown `RuntimeException` is caught by `DeviceBridge.getFirmwareVersion()` in Kotlin and converted via `parseSdkError()`.

### Android Kotlin layer

`NativeBridge.kt` declares `external fun nativeGetFirmwareVersion(handle: Long): String`. `DeviceBridge.kt` wraps it with `requireHandle()` + try/catch + `parseSdkError()` — identical to `getBatteryCharge()` (line 181). Plugin dispatch is a one-liner matching the other simple getter lines.

### Pre-condition enforcement

The C API header states: "Only contains info after device is connected." The Dart layer guards with `_checkConnected()` (throws `DeviceNotConnectedException`). If called on native side without connection, `clCError` propagates correctly through each platform's error path.

### Thread safety

Synchronous getter invoked on the platform thread via MethodChannel. No callbacks, no background threading concerns.

### Memory management

`clCDevice_GetFirmwareVersion` returns `const char*` — a pointer to SDK-internal memory (same ownership as `clCDeviceInfo_GetSerial`). Both platforms copy the string (`String(cString:)` on iOS, `NewStringUTF` on Android). No leak.

### Critical Issues

None.

### Non-Critical Issues

None.

REVIEW_PASS
