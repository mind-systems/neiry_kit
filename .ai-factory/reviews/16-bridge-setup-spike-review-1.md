## Code Review Summary

**Plan:** `16-bridge-setup-spike.md`
**Files Changed:** 4 (code) + 3 (plan/review artifacts)
**Risk Level:** 🔴 High

### Critical Issues

1. **Plugin instance not retained — all MethodChannel calls will hang at runtime**

   `NeiryKitPlugin.swift:13-17`

   ```swift
   public static func register(with registrar: FlutterPluginRegistrar) {
       let instance = NeiryKitPlugin(registrar: registrar)
       instance.registerMethodChannels()
       instance.registerEventChannels()
   }
   ```

   `instance` is a local variable. After `register(with:)` returns, nothing holds a strong reference to it. The plan explicitly chose `setMethodCallHandler` over `addMethodCallDelegate` — but `addMethodCallDelegate` is what causes the registrar to retain the plugin instance. Without it, ARC deallocates the instance.

   The method call closures (line 36) capture `[weak self]`:
   ```swift
   channel.setMethodCallHandler { [weak self] call, result in
       self?.handleMethodCall(call, result: result, channelId: id)
   }
   ```

   Once `self` is nil, `self?.handleMethodCall(...)` is a no-op. The `result` callback is **never invoked**. On the Dart side, `invokeMethod<String>('getVersionString')` returns a `Future` that never completes — the button press hangs forever with no error, no timeout, no feedback.

   This defeats the entire purpose of the spike: it will compile successfully but silently fail at runtime, giving a false negative ("linking doesn't work") when the real problem is object lifetime.

   **Fix:** Store the instance in a static property so it survives beyond `register(with:)`:

   ```swift
   private static var instance: NeiryKitPlugin?

   public static func register(with registrar: FlutterPluginRegistrar) {
       let instance = NeiryKitPlugin(registrar: registrar)
       self.instance = instance
       instance.registerMethodChannels()
       instance.registerEventChannels()
   }
   ```

   This is the standard pattern for Flutter iOS plugins that use `setMethodCallHandler` instead of `addMethodCallDelegate`.

### Verified Correct

- **All 8 MethodChannel IDs** match `NeiryChannels` in `channel_names.dart` character-for-character.
- **All 29 EventChannel IDs** match `NeiryEvents` in `channel_names.dart` character-for-character.
- **Umbrella header** `NeiryKitBridge.h` includes `CCapsuleAPI.h` which exists at `official/iOS/CapsuleClient.framework/Headers/CCapsuleAPI.h` and pulls in all 17 C headers including `CDeviceLocator.h`.
- **`clCCapsule_GetVersionString()`** is declared in `CDeviceLocator.h:32` as `const char*` — `String(cString:)` is the correct Swift conversion.
- **Podspec** `s.public_header_files = 'Classes/**/*.h'` is correctly placed and the existing `HEADER_SEARCH_PATHS` resolves the quoted `#include "CCapsuleAPI.h"`.
- **`StubStreamHandler`** instances are independently retained by the binary messenger (they're captured strongly in the `setStreamHandler` closure), so EventChannel registration is unaffected by the retention bug — stubs will work correctly.
- **Example app** Dart code correctly uses `const MethodChannel(...)`, handles `PlatformException`, and displays the result. The spike UI is clean and functional.
- **`registrar` stored as instance property** per the plan's suggestion — ready for future Bluetooth permission prompts.
