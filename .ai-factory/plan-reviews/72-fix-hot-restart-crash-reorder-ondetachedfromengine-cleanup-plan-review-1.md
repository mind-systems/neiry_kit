# Plan Review: Fix hot restart crash — reorder onDetachedFromEngine cleanup

**Plan:** `.ai-factory/plans/72-fix-hot-restart-crash-reorder-ondetachedfromengine-cleanup.md`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** OK — change stays inside the Android platform-bridge layer and respects the bridge ownership boundary (`NeiryKitPlugin` owns lifecycle of all bridges).
- **Rules (`.ai-factory/RULES.md`):** Not present — no explicit rules to check. WARN: optional file missing.
- **Roadmap (`.ai-factory/ROADMAP.md`):** Bugfix scope; roadmap linkage not required for this kind of stability fix.
- **Skill context (`.ai-factory/skill-context/aif-review/SKILL.md`):** Not present.

## Codebase Verification

Verified the plan's assumptions against the current source:

1. **File path is correct.** `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt` exists and contains `onDetachedFromEngine`.
2. **Line numbers are accurate.** The bridge teardown block in `onDetachedFromEngine` lives at lines 500–519 (the cleanup statements themselves are 501–519; lines 521–529 hold the `methodChannels` / `eventChannels` teardown that the plan leaves alone). Match is good.
3. **Current order matches the plan's description.**
   - Classifiers first (501–514): productivity → mems → cardio → physio → emotions → nfbCalibrator → nfb.
   - Then `deviceLocatorBridge?.dispose()` (515) and `deviceBridge?.release()` (516).
   - Then null-assignments (517–519) and channel cleanup.
4. **Classifier `dispose()` semantics verified.** `EmotionsBridge.dispose()` → `nativeBridge.nativeDisposeEmotions(handle)` → in `jni_emotions.cpp` calls `clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, nullptr)` and `clCEmotions_SetOnErrorEvent(emotions, nullptr)`. That is exactly the path the plan blames. Other classifier JNIs (`jni_physio.cpp`, `jni_cardio.cpp`, etc.) follow the same pattern.
5. **`DeviceBridge.release()` already unregisters callbacks before releasing the native handle** (`nativeUnregisterDeviceCallbacks` then `nativeReleaseDevice`), so reordering it earlier in the teardown is safe — no risk of stray device callbacks landing on dead Flutter sinks during the new window.
6. **Bridge ordering preserved.** Plan keeps the relative order of the seven classifier bridges identical to the current code. Verified.

## Findings

### Critical Issues
None.

### Important Notes

1. **The plan also reverses `deviceLocator` vs `deviceBridge` order** (current: locator.dispose() at 515, device.release() at 516 → proposed: device.release() first, then locator.dispose()). This reversal is desirable on its own merits — the locator owns/produces devices, and destroying the locator first could free the device's C++ object out from under `deviceBridge.handle`, turning the subsequent `deviceBridge.release()` into a use-after-free of `clCDevice`. The plan would benefit from one sentence acknowledging that this is an intentional secondary fix, not just a side-effect of moving classifiers down.

2. **Hypothesis assumes the SDK tolerates classifier teardown after `clCDevice_Release`.** Releasing the device first solves the crash only if the SDK's internal `IsClassifierSupported()` short-circuits (or returns gracefully) when the underlying device has been released, rather than dereferencing a freed `clCDevice`. The plan presents this as a tested observation — fine, but worth keeping in mind that if a future SDK upgrade changes that semantics the fix regresses. No code change requested; just a note for the verifier and for future maintenance.

3. **Scope limitation is correct.** The user-invoked `"dispose"` path on `DeviceLocator` (line 191) is not touched, and shouldn't be — that path is invoked by Dart code on a live BLE link, not on engine detach. iOS is also out of scope; `NeiryKitPlugin.swift` does not implement `detachFromEngine` and the iOS Flutter lifecycle differs.

4. **Minor:** plan says "currently lines 500–519" — the cleanup statements that move are actually 501–519 (line 500 is the function signature). Trivial, doesn't affect implementation.

### Positive Notes

- Tightly scoped: one file, one method, no API changes, no migrations.
- Preserves classifier ordering exactly, eliminating a class of accidental behavioural changes.
- Explicitly forbids touching other methods/files — keeps the diff reviewable.
- Diagnosis (signal 6 from `IsClassifierSupported` on a dead BLE link) is consistent with the codebase: every classifier dispose ultimately calls `SetOnXxxUpdateEvent(handle, nullptr)`, which is the call the plan blames.
- `Settings: Testing: no, Logging: minimal, Docs: no` is appropriate for a single-line-reorder native-crash fix.

## Verdict

The plan correctly identifies the file, the lines, the failure path, and the corrective ordering. The proposed new sequence (device.release → locator.dispose → classifiers) is sound and additionally fixes a latent locator-before-device ordering bug. Implementation as written is safe to proceed.

PLAN_REVIEW_PASS
