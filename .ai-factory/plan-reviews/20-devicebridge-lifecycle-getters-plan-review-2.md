## Code Review Summary

**Plan Reviewed:** `.ai-factory/plans/20-devicebridge-lifecycle-getters.md`
**Files Affected:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** No violations. The `requireDevice()` helper uses only the stored handle — no cross-bridge access. The `NeiryKitPlugin` mediates the handle handoff via `setDevice`, respecting the "bridges must never cross-call each other" rule.
- **RULES.md:** file does not exist — `WARN` (non-blocking).
- **ROADMAP.md:** plan aligns with the "DeviceBridge — lifecycle + getters" milestone. All scope items are covered.

### Review-1 Fix Verification

All five issues and suggestions from plan-review-1 were addressed:
1. `resolveDevice` cross-bridge access → replaced with `requireDevice()` that only checks `self.device`. ✓
2. `release()` called on disconnect → plan now explicitly states disconnect does NOT call release. ✓
3. Simplify to `requireDevice()` → adopted. ✓
4. `isConnected` omission documented → explicit note added explaining client-side tracking. ✓
5. Channel names caching made definitive → `MUST be cached`, `channelNamesHandle` property added in Task 1. ✓

### Critical Issues

None.

### Suggestions

1. **`setDevice` same-serial handle replacement**
   Task 1: the condition `self.device != nil && self.serial != serial` skips release when `createDevice` is called twice with the same serial. In that scenario handle A leaks and `channelNamesHandle` becomes stale (still points to A's internal data while `self.device` now holds handle B).
   Fix: change the guard to `self.device != nil` (always release + nil channelNamesHandle when replacing), with an additional `self.device != handle` check to avoid releasing the same pointer being stored:
   ```swift
   if let old = self.device, old != handle {
       clCDevice_Release(old)
       channelNamesHandle = nil
   }
   ```
   This is an edge case — the Dart API makes double-creation unlikely — but the fix is one line and makes the bridge unconditionally safe.

### Positive Notes

- All C API function signatures verified against `CDevice.h` and `CDeviceInfo.h` — every parameter, return type, and error-handling decision is correct. `clCDevice_GetMode` correctly marked as no-`clCError*`; `clCDeviceInfo_Get*` accessors correctly treated as error-free.
- Return types align precisely with Dart expectations: `Float` for sample rates (Dart receives as `num`, calls `.toDouble()`), `Int32` for PPG amplitudes (Dart receives as `int`), `Int(rawValue)` for mode/type enums (matches `NeiryDeviceType.fromCode` / `NeiryDeviceMode.fromCode`).
- `getInfo` map keys (`serial`, `name`, `type`) match `DeviceInfo.fromMap` exactly, and the `Int(clCDeviceInfo_GetType(info).rawValue)` pattern matches the proven `DeviceLocatorBridge` code.
- Channel names two-step handle caching is well-designed. Confirmed: `clCDevice_ChannelNames` is a const-pointer to device-internal data with no release function — caching avoids redundant cross-boundary calls.
- The `release()` / `disconnect` separation is correctly modeled: disconnect is a BLE operation, release is a handle-lifetime operation. The plan correctly keeps them independent.
- Task 6 dispatch is complete — all 16 methods from `DeviceMethods` (minus `createDevice` handled by locator and `isConnected` tracked client-side) are accounted for.
- Commit plan (skeleton+lifecycle → getters → wiring) provides clean, reviewable increments.

PLAN_REVIEW_PASS
