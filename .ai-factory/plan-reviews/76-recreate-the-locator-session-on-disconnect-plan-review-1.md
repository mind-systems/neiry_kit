# Plan Review: Recreate the locator session on disconnect

**Plan:** `.ai-factory/plans/76-recreate-the-locator-session-on-disconnect.md`
**Files Reviewed:** 1 plan + `example/lib/services/neiry_service.dart`, `lib/src/api/device_locator.dart`, `ARCHITECTURE.md`, `ROADMAP.md`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** PASS. The change lives entirely in `example/`, which the dependency rules explicitly allow to use the `lib/` public API (`DeviceLocator`, `dispose()` are public via the barrel). No plugin-internal `src/` import, no layer violation. No `ios/`/`android/` native change is required — verified below.
- **Rules (`.ai-factory/RULES.md`):** WARN — file not present. No project-specific rule set to enforce. No `aif-review` skill-context SKILL.md present either, so only general rules apply.
- **Roadmap (`.ai-factory/ROADMAP.md`):** PASS. Milestone at line 114 — *"Recreate the locator session on disconnect"* (`[ ]`, in progress) — matches the plan one-to-one: make `_locator` mutable, `await _locator.dispose()` then `_locator = DeviceLocator()` at end of `disconnect()`, guarded by `!_disposed`. Spec note `.ai-factory/notes/29-recreate-locator-session-on-disconnect.md` is referenced. Linkage is clean.

## Verification of Plan Claims

Every cited line number and API claim was checked against the current source:

- ✅ Line 18 constructor `NeiryService() : _locator = DeviceLocator();` — exact match.
- ✅ Line 22 `final DeviceLocator _locator;` — exact match; mutability change is correct.
- ✅ Lines 343–345 device-scoped resets `_device = null; _nfbData = null; _calibrator = null;` — exact match; insertion point (very end of `disconnect()`) is correct.
- ✅ `dispose()` at lines 379–383: sets `_disposed = true` (381) *before* `await disconnect()` (382), then runs its own `await _locator.dispose()` (383). The `!_disposed` guard logic is sound — during full teardown the recreate is skipped, so the locator is disposed exactly once.
- ✅ `DeviceLocator.dispose()` (device_locator.dart:269–291) calls `_checkNotDisposed()` first (270) and would throw `StateError` on double-dispose — confirming the guard is genuinely mandatory, not cosmetic.
- ✅ Singleton recreate works: `dispose()` sets `_instance = null` (291/283) and the factory `_instance ??= ...` (60) then builds a fresh native locator on the next `DeviceLocator()`. The plan's "genuinely fresh native locator" claim holds.
- ✅ No native ordering race: `dispose()` awaits the native `destroy` `invokeMethod` before nulling `_instance`; the new locator's `create` is dispatched in its constructor and `createDevice()` awaits `_nativeReady`. Destroy→create cannot overlap.
- ✅ `connect()`/`scan()` read `_locator` at call time (lines 100, 126) — they pick up the recreated instance with no further change, as the plan states.
- ✅ `nlog(..., name: 'neiry_kit')` matches the existing import (line 5) and call style throughout the file.

## Critical Issues

None. The plan is technically correct, scoped tightly, and the guard reasoning is airtight.

## Minor Observations (non-blocking)

1. **Idle-config not lost on recreate — confirmed safe.** A potential concern is that `DeviceLocator()` is reconstructed with no `logDirectory` and resets to default multi-threaded mode. A grep of `example/` shows no use of `setSingleThreaded` or `logDirectory`, and `NeiryService` itself constructs with `DeviceLocator()` (no args). So the recreate preserves the same configuration the app already used. No action needed; just noting the assumption was checked.

2. **Early-return path is not covered (acceptable).** `disconnect()` returns at line 254 when `_device == null`, so the recreate never runs in that case. This is fine — with no device there is no cached `clCDevice`/stuck calibrator to evict. One adjacent edge case lies outside this plan: a `connect()` that fails mid-flight (catch block lines 131–138) disposes the device and leaves `_device == null` without recreating the locator, so a cached half-initialized device could persist in the singleton. This is pre-existing, out of scope for the stated bug, and need not block the plan — but is worth keeping in mind if repeat-connect-after-failure ever misbehaves.

3. **Pre-existing comment numbering.** The inline comment at line 342 labels the device-field reset as step "4", duplicating the "4. Disconnect" label at line 322. The new block lands right after this. Not introduced by the plan; a one-word fix (renumber to step 6 and label the recreate as step 7) would tidy the sequence if the implementer touches the comments anyway. Optional.

## Positive Notes

- Root-cause framing (SDK caches `clCDevice` per serial in the locator singleton; `clCDevice_Release` does not evict; calibrator has no stop/reset API) is accurate and matches the ROADMAP/spec.
- The plan correctly resists the tempting-but-wrong "reset the calibrator" hack and uses the only SDK-sanctioned reset (locator teardown).
- The `await` before recreate and the `try/catch` around `_locator.dispose()` correctly mirror the existing defensive style in `disconnect()`.
- Scope is minimal: one field modifier + one guarded block, no native code, no API surface change.

PLAN_REVIEW_PASS
