## Code Review Summary

**Plan:** `16-bridge-setup-spike.md`
**Files Changed:** 4 (code) + 5 (plan/review/orchestrator artifacts)
**Risk Level:** 🟢 Low

### Prior Review Issues — Resolved

Review 1 found one critical issue: the plugin instance was not retained after `register(with:)` returned, causing `[weak self]` to become nil and all MethodChannel calls to hang forever.

**Fix applied:** `private static var instance: NeiryKitPlugin?` added (line 5) and `self.instance = instance` in `register(with:)` (line 17). The static property prevents ARC deallocation. This is the standard Flutter iOS plugin pattern when using `setMethodCallHandler` instead of `addMethodCallDelegate`.

### Critical Issues

None.

### Verification

**MethodChannel IDs** — all 8 strings in `NeiryKitPlugin.swift:27-34` verified character-by-character against `NeiryChannels` in `channel_names.dart:11-18`. All match.

**EventChannel IDs** — all 29 strings in `NeiryKitPlugin.swift:64-92` verified character-by-character against `NeiryEvents` in `channel_names.dart:27-65`. All match.

**Spike method name** — `"getVersionString"` in Swift (line 48), Dart example app (line 32), and `DeviceLocatorMethods.getVersionString` (channel_names.dart:80) all match.

**C function signature** — `clCCapsule_GetVersionString()` declared in `CDeviceLocator.h:32` as `CL_DLL const char* clCCapsule_GetVersionString() NOEXCEPT;`. The Swift call `String(cString: clCCapsule_GetVersionString())` is the correct conversion from `const char*`.

**Umbrella header chain** — `NeiryKitBridge.h` includes `CCapsuleAPI.h` (confirmed present at `official/iOS/CapsuleClient.framework/Headers/CCapsuleAPI.h`), which includes all 17 C SDK headers. The podspec's `HEADER_SEARCH_PATHS` points to that directory. Quoted `#include` resolves correctly with this configuration.

**Podspec** — `s.public_header_files = 'Classes/**/*.h'` is correctly placed after `s.source_files`, making the umbrella header visible to the Swift compiler.

**Hot restart safety** — When `register(with:)` is called again (hot restart), `self.instance` is overwritten. Old closures become no-ops via `[weak self]` (correct — old channels are superseded). New `setMethodCallHandler` calls overwrite the binary messenger's handler map for the same channel names. No leak, no crash.

**Example app** — `const MethodChannel('neiry_kit/device_locator')` uses the correct channel ID. Error handling catches `PlatformException`. Null response handled with `?? '(null)'`.

REVIEW_PASS
