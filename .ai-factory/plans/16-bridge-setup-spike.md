# Plan: Bridge Setup + Spike

## Context

Set up the iOS native bridge infrastructure so Swift code can call the Capsule C SDK, then prove it works by calling `clCCapsule_GetVersionString()`. This is the foundation for all subsequent iOS bridge milestones — no real SDK logic yet, just channel registration and a compilation spike.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: C header visibility

- [x] **Task 1: Create umbrella header and update podspec**
  Files: `ios/Classes/NeiryKitBridge.h`, `ios/neiry_kit.podspec`

  Create `ios/Classes/NeiryKitBridge.h` — a standard Objective-C umbrella header that makes all Capsule C functions visible to Swift:
  ```objc
  #ifndef NeiryKitBridge_h
  #define NeiryKitBridge_h
  #include "CCapsuleAPI.h"
  #endif
  ```
  This single include pulls in all 19 C headers (`CDevice.h`, `CDeviceLocator.h`, `CNFB.h`, etc.) because `CCapsuleAPI.h` is itself an umbrella inside the framework.

  **Important:** The quoted `#include "CCapsuleAPI.h"` resolves because the podspec's `HEADER_SEARCH_PATHS` already points to the framework's `Headers/` directory. Do not use angle brackets (`#include <CCapsuleAPI.h>`) — that requires a framework-style search path which is not configured.

  In `ios/neiry_kit.podspec`, add `s.public_header_files = 'Classes/**/*.h'` right after the existing `s.source_files` line. The podspec already has `s.vendored_frameworks` and the correct `HEADER_SEARCH_PATHS` — no other podspec changes needed.

### Phase 2: Channel registration

- [x] **Task 2: Rewrite NeiryKitPlugin.swift — register 8 MethodChannels with stub closures**
  Files: `ios/Classes/NeiryKitPlugin.swift`

  Replace the entire boilerplate `NeiryKitPlugin.swift` with a proper multi-channel plugin. The current file registers a single `"neiry_kit"` channel and only handles `"getPlatformVersion"` — discard all of that.

  In `register(with:)`:
  - Store `registrar` as an instance property on the plugin (`private let registrar: FlutterPluginRegistrar`). Future bridge milestones will need the registrar to access the view controller (e.g., for Bluetooth permission prompts on iOS 13+).
  - Create 8 `FlutterMethodChannel` instances using the exact IDs from the Dart contract (`NeiryChannels` in `lib/src/channel/channel_names.dart`):
    - `neiry_kit/device_locator`
    - `neiry_kit/device`
    - `neiry_kit/nfb`
    - `neiry_kit/physiological`
    - `neiry_kit/emotions`
    - `neiry_kit/productivity`
    - `neiry_kit/cardio`
    - `neiry_kit/nfb_calibrator`
  - Store all channels in a `[String: FlutterMethodChannel]` dictionary as an instance property so future bridge classes can reference them.
  - For each channel, call `channel.setMethodCallHandler { call, result in result(FlutterMethodNotImplemented) }`. Each closure captures the plugin instance and returns `FlutterMethodNotImplemented` for all methods. This per-channel closure pattern lets future bridges replace their own closure without touching other channels' registration code.
  - Do NOT use `addMethodCallDelegate` — `setMethodCallHandler` and `addMethodCallDelegate` are mutually exclusive per channel.

- [x] **Task 3: Register all EventChannels with a stub stream handler**
  Files: `ios/Classes/NeiryKitPlugin.swift`

  Create a private `StubStreamHandler` class implementing `FlutterStreamHandler`:
  ```swift
  private class StubStreamHandler: NSObject, FlutterStreamHandler {
      func onListen(withArguments arguments: Any?,
                    eventSink events: @escaping FlutterEventSink) -> FlutterError? {
          return nil
      }
      func onCancel(withArguments arguments: Any?) -> FlutterError? {
          return nil
      }
  }
  ```

  In `register(with:)`, create a `FlutterEventChannel` for each of the 29 IDs from `NeiryEvents` and set the stub handler. All 29 event channel IDs (copy exactly from `lib/src/channel/channel_names.dart`):

  `neiry_kit/events/deviceList`, `neiry_kit/events/eeg`, `neiry_kit/events/psd`, `neiry_kit/events/eegArtifacts`, `neiry_kit/events/resistance`, `neiry_kit/events/battery`, `neiry_kit/events/connectionStatus`, `neiry_kit/events/modeSwitched`, `neiry_kit/events/nfbState`, `neiry_kit/events/physiologicalState`, `neiry_kit/events/emotionsState`, `neiry_kit/events/productivityMetrics`, `neiry_kit/events/productivityIndexes`, `neiry_kit/events/cardioData`, `neiry_kit/events/ppgData`, `neiry_kit/events/memsData`, `neiry_kit/events/nfbCalibration`, `neiry_kit/events/physiologicalCalibrationProgress`, `neiry_kit/events/physiologicalCalibrated`, `neiry_kit/events/physiologicalIndividualNfb`, `neiry_kit/events/productivityCalibrationProgress`, `neiry_kit/events/productivityCalibrated`, `neiry_kit/events/productivityBaselines`, `neiry_kit/events/productivityIndividualNfb`, `neiry_kit/events/cardioCalibratedEvent`, `neiry_kit/events/error`, `neiry_kit/events/nfbError`, `neiry_kit/events/emotionsError`, `neiry_kit/events/productivityError`.

  Store EventChannel references in a `[String: FlutterEventChannel]` dictionary on the plugin instance — future bridge milestones will replace stub handlers with real ones.

  Note: the roadmap milestone says "22 EventChannels" but the actual Dart contract defines 29. Register all 29 to stay in sync with the contract.

  **Lifecycle note:** `StubStreamHandler` exists only for this spike milestone. Remove it once all real bridges are connected and every EventChannel has its own dedicated stream handler.

### Phase 3: Compilation spike

- [x] **Task 4: Implement `getVersionString` to verify C SDK compiles and links**
  Files: `ios/Classes/NeiryKitPlugin.swift`

  In the `deviceLocator` MethodChannel handler (the closure set in Task 2), replace the `FlutterMethodNotImplemented` branch for method name `"getVersionString"` with a real implementation:
  ```swift
  case "getVersionString":
      let version = String(cString: clCCapsule_GetVersionString())
      result(version)
  ```
  `clCCapsule_GetVersionString()` is declared in `CCapsuleAPI.h` (included via the umbrella header from Task 1) and returns a `const char*`. If this compiles and returns a string at runtime, the entire C SDK linking chain is confirmed working: podspec → vendored framework → header search paths → umbrella header → Swift bridging → C function call.

  The method name constant `DeviceLocatorMethods.getVersionString` exists in the Dart contract (`channel_names.dart`), but the `DeviceLocator` class does **not** expose a `getVersionString()` method — it is a debug utility, not a consumer-facing API. Task 5 adds the Dart-side call to exercise this spike.

- [x] **Task 5: Add a Dart-side spike call to verify runtime linking**
  Files: `example/lib/main.dart`

  The `DeviceLocator` class intentionally does not have a `getVersionString()` method (it's a debug utility, not part of the public API). To prove the native bridge works at runtime — not just at compile time — add a direct MethodChannel call in the example app.

  In the example app's main screen (or a dedicated "SDK Info" section), invoke the spike:
  ```dart
  final version = await const MethodChannel('neiry_kit/device_locator')
      .invokeMethod<String>('getVersionString');
  ```
  Display the returned version string in the UI (e.g., a `Text` widget or `print` statement). If the string appears, the full native linking chain is confirmed end-to-end: Dart → MethodChannel → Swift closure → C function → response.

  This is a temporary spike verification — it can be removed or replaced with a proper public API method in a later milestone if needed.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Register all MethodChannels and EventChannels with stub handlers"
- **Commit 2** (after tasks 4-5): "Add getVersionString spike to verify C SDK linking end-to-end"
