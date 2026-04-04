## Code Review Summary

**Plan Reviewed:** `16-bridge-setup-spike.md`
**Files Referenced:** 6
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — plan aligns with the layered bridge architecture. The preferred `setMethodCallHandler` pattern deviates from the spec's `addMethodCallDelegate` example, but the plan acknowledges this explicitly and the reasoning is sound.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** WARN — plan correctly identifies the EventChannel count discrepancy (roadmap says 22, Dart contract defines 29) and aligns with the contract. Roadmap should be updated after implementation.

### Critical Issues

1. **Wrong claim: `getVersionString` is NOT wired in `DeviceLocator`**

   Task 4 states: *"This method is already declared in the Dart contract as `DeviceLocatorMethods.getVersionString` and wired in `DeviceLocator` — no Dart changes needed."*

   The constant `DeviceLocatorMethods.getVersionString` exists in `channel_names.dart`, but the `DeviceLocator` class (`lib/src/api/device_locator.dart`) has **no `getVersionString()` method**. The class only exposes `requestDevices`, `createDevice`, `setSingleThreaded`, `update`, and `dispose`.

   This means there is no way to invoke the spike from Dart unless the implementer either:
   - (a) adds a `getVersionString()` method to `DeviceLocator`, or
   - (b) calls `MethodChannel('neiry_kit/device_locator').invokeMethod('getVersionString')` directly from the example app or a test.

   The plan must pick one and include it as a task. Without this, the spike only proves compilation — not runtime linking. Option (b) is simpler and keeps the Dart public API clean (a version-string getter is a debug utility, not a consumer-facing method).

2. **Contradictory channel registration instructions in Task 2**

   Task 2 first describes the `addMethodCallDelegate` pattern in detail (dictionary dispatch, single `handle` method), then says "Alternative (preferred) pattern: use `setMethodCallHandler` closures" and warns the two are mutually exclusive. The implementer gets two full designs and must choose.

   Pick one. Remove the non-preferred approach entirely to avoid confusion. The `setMethodCallHandler` closure pattern is the right one — it's cleaner, each bridge owns its closure, and it avoids the single-`handle` dispatch problem. Delete the `addMethodCallDelegate` + dictionary dispatch paragraph.

### Suggestions

1. **Task 2 — store `registrar` reference on the plugin instance**

   Future bridge milestones will need the `FlutterPluginRegistrar` to access the view controller (e.g., for Bluetooth permission prompts on iOS 13+). Task 2 should store `registrar` as an instance property alongside the channel dictionaries. Adding it later means touching the registration code again.

2. **Task 1 — verify `#include` resolves at the right path**

   The umbrella header uses `#include "CCapsuleAPI.h"` with a quoted include. This works only if `HEADER_SEARCH_PATHS` in the podspec points to the framework's `Headers/` directory — which it does. Worth adding a one-line comment in the plan noting this dependency, so the implementer doesn't accidentally use angle brackets (`#include <CCapsuleAPI.h>`) which would require a different search path setup.

3. **Task 3 — `StubStreamHandler` should be a top-level `private` class, not nested**

   The plan puts `StubStreamHandler` inside `NeiryKitPlugin.swift` as a private class. That's fine for now, but once real bridges replace stubs, this class becomes dead code. Add a brief note: "Remove `StubStreamHandler` once all real bridges are connected — it exists only for this spike milestone."

### Positive Notes

- Correct identification that the Dart contract defines 29 EventChannels, not the 22 stated in the roadmap. Registering all 29 avoids a sync-up task later.
- The plan correctly traces the full linking chain (podspec → vendored framework → header search paths → umbrella header → Swift bridging → C function call) and explains *why* the spike proves it works.
- Clean phasing: header visibility → channel registration → compilation proof. Each phase has a clear deliverable.
- The `setMethodCallHandler` closure approach is well-reasoned — per-channel closures let future bridges slot in without touching the plugin's core registration code.
