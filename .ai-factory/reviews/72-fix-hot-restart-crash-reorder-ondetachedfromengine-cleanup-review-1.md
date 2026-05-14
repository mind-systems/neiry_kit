# Code Review: Fix hot restart crash — reorder onDetachedFromEngine cleanup

**Plan:** `.ai-factory/plans/72-fix-hot-restart-crash-reorder-ondetachedfromengine-cleanup.md`
**Reviewed file:** `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
**Risk Level:** 🟢 Low

## Scope of change

`git diff HEAD` shows a single source-code change: lines reordered inside `NeiryKitPlugin.onDetachedFromEngine` (around lines 500–519 of `NeiryKitPlugin.kt`). No other source files are modified. The two new tracked files under `.ai-factory/` are the plan and a prior plan-review — not runtime code.

The new order in `onDetachedFromEngine` (verified by reading the file):

1. `deviceBridge?.release()` + `deviceBridge = null`
2. `deviceLocatorBridge?.dispose()` + `deviceLocatorBridge = null`
3. `productivityBridge`, `memsBridge`, `cardioBridge`, `physioBridge`, `emotionsBridge`, `nfbCalibratorBridge`, `nfbBridge` — each disposed and nulled, in their original relative order
4. `nativeBridge = null`
5. `methodChannels` / `eventChannels` teardown blocks — unchanged

## Plan compliance

- ✅ `deviceBridge?.release()` is the first statement in the method, immediately followed by `deviceBridge = null` (plan step 1).
- ✅ `deviceLocatorBridge?.dispose()` then `deviceLocatorBridge = null` come next (plan step 2).
- ✅ The seven classifier bridges are disposed in the original order: productivity → mems → cardio → physio → emotions → nfbCalibrator → nfb (plan step 3, "do not change relative order").
- ✅ `nativeBridge = null` and the channel teardown blocks remain in their original positions after the bridge cleanup (plan step 4).
- ✅ No other methods, files, or behavior touched.

## Correctness checks

- **No new null-deref risk.** Each bridge is dereferenced with `?.`, matching the existing style. Setting `deviceBridge = null` before disposing classifiers is fine because no classifier `dispose()` consults `deviceBridge` — they call into their own native handles via `nativeBridge`, which is still non-null at that point (it's nulled only at line 519, after all classifier disposes).
- **`nativeBridge` lifetime.** The order keeps `nativeBridge` alive across every classifier dispose call and only nulls it afterwards — same as before. No regression.
- **Channel teardown ordering.** `methodChannels` / `eventChannels` are still torn down last, after all bridges are gone, so no stray method/event delivery can reach a bridge after dispose.
- **Thread-safety window.** The new order opens a brief window where the device is released but classifiers are still alive. If an SDK background callback fires for a classifier in that window, the classifier still holds its own native handle and the EventChannel sink is still installed, so behavior matches the pre-fix steady state in that window. The fix relies on the SDK's `clCXxx_SetOnXxxUpdateEvent(handle, nullptr)` (called during classifier dispose) tolerating a released device — this is an inherent assumption of the chosen fix strategy, called out in the plan-review; not a bug introduced by this diff.
- **iOS untouched.** As noted by the plan, iOS has no `onDetachedFromEngine` equivalent; no Swift code changed.
- **No type, signature, or API surface change.** Pure statement reordering; no callers affected.

## Findings

None. The diff implements the plan exactly and introduces no regressions discoverable from the source.

REVIEW_PASS
