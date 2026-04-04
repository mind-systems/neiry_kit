## Code Review Summary

**Plan Reviewed:** `16-bridge-setup-spike.md`
**Files Referenced:** 7
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge architecture. Per-channel `setMethodCallHandler` closures align with the "each bridge owns its own channels" dependency rule. The umbrella header approach matches the documented iOS bridge pattern.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** PASS — plan targets the "bridge setup + spike" milestone. The EventChannel count discrepancy (roadmap: 22, contract: 29) is explicitly acknowledged and the plan correctly follows the Dart contract as source of truth.

### Prior Review Issues — All Resolved

Review 1 raised two critical issues and three suggestions. All have been addressed:

1. ~~Missing Dart-side spike call~~ — Task 5 now adds a direct `MethodChannel` call in the example app, and Tasks 4–5 both correctly note that `DeviceLocator` intentionally has no `getVersionString()` method.
2. ~~Contradictory `addMethodCallDelegate` vs `setMethodCallHandler`~~ — Task 2 now exclusively uses `setMethodCallHandler` with an explicit "Do NOT use `addMethodCallDelegate`" note.
3. ~~Store `registrar`~~ — Task 2 stores `registrar` as an instance property with rationale (future BT permission prompts).
4. ~~`#include` path note~~ — Task 1 has an **Important** block explaining quoted vs angle brackets and the `HEADER_SEARCH_PATHS` dependency.
5. ~~`StubStreamHandler` lifecycle~~ — Task 3 has a **Lifecycle note** marking it for removal once real bridges are connected.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- All 8 MethodChannel IDs in Task 2 match `NeiryChannels` in `channel_names.dart` exactly.
- All 29 EventChannel IDs in Task 3 match `NeiryEvents` in `channel_names.dart` exactly — verified character-by-character.
- `clCCapsule_GetVersionString()` confirmed in `CDeviceLocator.h` line 32: `CL_DLL const char* clCCapsule_GetVersionString() NOEXCEPT;` — returns `const char*`, and the Swift snippet `String(cString:)` is the correct conversion.
- The umbrella header approach (`NeiryKitBridge.h` → `CCapsuleAPI.h`) is the right solution given the framework has no `module.modulemap`. The podspec's `HEADER_SEARCH_PATHS` already resolves the quoted `#include` path.
- Task 5's direct `MethodChannel` call in the example app is the correct choice — it proves runtime linking end-to-end without polluting the public Dart API with debug methods.
- Clean two-commit plan: infrastructure first (stubs), then spike proof. Each commit is independently buildable.
- The plan is well-scoped — it touches only the iOS side and example app, leaving Android for its own future milestone.

PLAN_REVIEW_PASS
