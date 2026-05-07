# Plan: firmwareVersion getter — Dart + iOS + Android

## Context
Expose the new SDK v2.0.72 function `clCDevice_GetFirmwareVersion(clCDevice, clCError*) -> const char*` as a `Future<String> getFirmwareVersion()` method on the Dart `Device` class, with corresponding iOS (Swift) and Android (Kotlin + JNI) bridge implementations.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel contract + Dart API

- [x] **Task 1: Add `getFirmwareVersion` method constant to `DeviceMethods`**
  Files: `lib/src/channel/channel_names.dart`
  Add `static const getFirmwareVersion = 'getFirmwareVersion';` to the `DeviceMethods` class, after `getChannelsCount` (line ~102).

- [x] **Task 2: Add `getFirmwareVersion()` to Dart `Device` class**
  Files: `lib/src/api/device.dart`
  Add an async getter in the "Async getters" section (after `getChannelsCount()`), following the exact pattern of `getChannelName()` which also returns `String`:
  - Guard with `_checkNotDisposed()` and `_checkConnected()`.
  - Call `_channel.invokeMethod<String>(DeviceMethods.getFirmwareVersion, {NeiryArgs.serial: serial})`.
  - Return `result!`.

### Phase 2: iOS bridge

- [x] **Task 3: Add `getFirmwareVersion()` to `DeviceBridge.swift` and wire dispatch**
  Files: `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
  In `DeviceBridge.swift`, add a `getFirmwareVersion() throws -> String` method in the "Getters" section (after `getPPGRedAmplitude`). Follow the `getEEGSampleRate()` pattern:
  - `let dev = try requireDevice()`
  - `var error = clCError()`
  - `let result = clCDevice_GetFirmwareVersion(dev, &error)`
  - `try checkCError(error)`
  - Guard `result` is non-nil (throw `FlutterError(code: "NULL_RESULT", message: "clCDevice_GetFirmwareVersion returned nil", details: nil)`).
  - Return `String(cString: result!)`.

  In `NeiryKitPlugin.swift`, add a `case "getFirmwareVersion":` in `handleDeviceCall` (around line 306, before `default`), using the same do/catch pattern as `"getEEGSampleRate"`. Call `bridge.getFirmwareVersion()` and pass the result to `result(...)`.

### Phase 3: Android bridge

- [x] **Task 4: Add JNI function `nativeGetFirmwareVersion` in `jni_device.cpp`**
  Files: `android/src/main/cpp/jni_device.cpp`
  Add a new JNI function in the "Getters" section (after `nativeGetPPGRedAmplitude`), following the `nativeGetBatteryCharge` pattern but returning `jstring`:
  - Cast `handle` to `clCDevice` via `(clCDevice)(uintptr_t)handle`.
  - Call `clCDevice_GetFirmwareVersion(dev, &error)`.
  - On `!error.success`, call `throw_sdk_error(env, &error)` and return `nullptr`.
  - Return `env->NewStringUTF(result ? result : "")` — null-guard the C string before passing to JNI.

- [x] **Task 5: Add `external fun` + Kotlin bridge method + plugin dispatch**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NativeBridge.kt`, `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt`, `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  In `NativeBridge.kt`, add `external fun nativeGetFirmwareVersion(handle: Long): String` in the "Device" section (after `nativeGetPPGRedAmplitude`, line ~54).

  In `DeviceBridge.kt`, add `getFirmwareVersion(): String` in the "Getters" section, following the `getBatteryCharge()` pattern:
  - `val h = requireHandle()`
  - Wrap `nativeBridge.nativeGetFirmwareVersion(h)` in try/catch, rethrowing via `parseSdkError()`.

  In `NeiryKitPlugin.kt`, add `"getFirmwareVersion" -> result.success(bridge.getFirmwareVersion())` in the device dispatch `when` block (next to `"getBatteryCharge"`, around line 218).

## Commit Plan
- **Commit 1** (after tasks 1-5): "Add firmwareVersion getter across Dart, iOS, and Android layers"
