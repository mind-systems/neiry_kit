# Plan Review: Fix post-disconnect crash — guard native disconnect in Device.dispose()

**Plan:** `74-fix-post-disconnect-crash-guard-native-disconnect-in-device-dispose.md`
**Risk Level:** 🟢 Low
**Verdict:** Solid — approved

## Context Gates

- **Architecture** (`.ai-factory/ARCHITECTURE.md`): not present — WARN (optional file absent, no boundary check possible).
- **Rules** (`.ai-factory/RULES.md`): not present — WARN (optional file absent).
- **Roadmap** (`.ai-factory/ROADMAP.md`): not checked for linkage; this is a `fix` task. WARN — no roadmap linkage referenced in the plan, non-blocking.
- **Skill context** (`.ai-factory/skill-context/aif-review/SKILL.md`): not present — no project-specific overrides to apply.

## Verification Against the Codebase

All concrete claims in the plan were checked against `lib/src/api/device.dart`:

- **File path** `lib/src/api/device.dart` — correct.
- **Line range "around 221–234"** — exact. `dispose()` spans lines 221–234.
- **The misleading comment** `// Idempotent on the native side even if already disconnected.` exists verbatim at line 225 — correct target for replacement.
- **The native call to wrap** (`await _channel.invokeMethod<void>(DeviceMethods.disconnect, {NeiryArgs.serial: serial})`) is at lines 226–228 — correct.
- **State resets to keep** (`_started = false; _connected = false; _connectionState = ...; _mode = null; _battery = null;`) at lines 229–233 — correct, and matching the reset block in `disconnect()` (lines 187–192).
- **`!_connected` is `false` after `disconnect()` returns** — confirmed: `disconnect()` sets `_connected = false` at line 188 before returning.

## Crash Path Confirmed

The reported `Fatal signal 64` scenario is reproduced by real teardown code in `example/lib/services/neiry_service.dart` (lines 288–293):

```dart
try { await _device!.disconnect(); } catch (_) {}
try { await _device!.dispose(); } catch (_) {}
```

`disconnect()` runs the native disconnect and sets `_connected = false`; `dispose()` then runs the native disconnect a **second** time. The proposed `if (_connected)` guard skips that redundant second call — directly addressing the crash. The fix is minimal, scoped, and correct.

## Side-Effect Analysis (no regressions found)

- **`dispose()` on a still-connected device (no prior `disconnect()`)**: `_connected == true`, so the native disconnect runs exactly once. Sole-teardown path preserved. ✅
- **`dispose()` in the connect-failure path** (`neiry_service.dart:128`): `connect()` sets `_connected = true` only *after* the native call succeeds (line 174), so a thrown connect leaves `_connected == false` and the guarded native disconnect is skipped — correct, since native never established the connection. ✅
- **Existing test `test/api_test.dart:106`** (`methods after dispose() → throws StateError`): calls `dispose()` on a never-connected device. With the guard, the native disconnect is now skipped, but the test only asserts post-dispose `StateError` behavior (driven by `_disposed = true`), which is untouched. No test breakage. ✅
- **`_connected` flipped to `false` by the connection-state listener** (`_startStateTracking`, lines 139–142): if the device self-disconnected, `dispose()` correctly skips the native call. Desired behavior. ✅

## Observations (non-blocking)

1. **`disconnect()` itself remains unguarded.** A direct double `disconnect()` (without `dispose()`) would still invoke the native call twice. This is outside the reported crash path (which is `disconnect()` → `dispose()`) and outside the plan's stated scope, so it is acceptable to leave it. Worth a one-line awareness note for the implementer, but not a required change.

2. **Settings: `Logging: minimal`.** The plan adds no log line when the native call is skipped. This is consistent with the chosen setting; no action needed. Optionally a single `log(...)` on the skip branch would aid field debugging, but it is genuinely optional.

3. **Testing: no.** Given the change is a state-guarded branch and the crash is hardware/SDK-state dependent, skipping a new unit test is reasonable. The existing dispose test already exercises the new branch indirectly. Acceptable.

## Critical Issues

None.

## Positive Notes

- Plan correctly identifies the root cause (non-idempotent native SDK state machine) rather than papering over it with a try/catch.
- Replacing the inaccurate "idempotent" comment with the true rationale prevents a future regression where someone "simplifies" the guard away.
- Explicitly preserves the unconditional state resets so the disposed object stays fully locked down regardless of the guard outcome — a thoughtful detail.
- Single-file, no API surface change, no migration — appropriately narrow blast radius.

PLAN_REVIEW_PASS
