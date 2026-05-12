# Plan Review: 56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration

**Plan file:** `.ai-factory/plans/56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration.md`
**Files Reviewed:** 1 plan + 8 source files
**Risk Level:** 🔴 High — root-cause diagnosis is incorrect; the proposed fix will not stop the crash

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** present, no boundary issues from the proposed changes. PASS.
- **Rules (`.ai-factory/RULES.md`):** not present. SKIP.
- **Roadmap (`.ai-factory/ROADMAP.md`):** present, but task 56 is a fix and is not required to be linked. SKIP.
- **Skill-context (`.ai-factory/skill-context/`):** not present. SKIP.

## Critical Issues

### 1. The proposed fix does not address the actual root cause of the crash

The plan's **Context** asserts:

> "Riverpod rebuilds the classifier notifier (calling `clCProductivity_Create` / `clCCardio_Create` / `clCMEMS_Create`) before `ref.onDispose` releases the previous instance, and the SDK aborts on a second `Create` for the same device."

This diagnosis is incomplete and the proposed fix cannot work, for three compounding reasons:

#### a) `dispose()` on a classifier is **not** synchronous and does **not** release the SDK handle

`ProductivityClassifier.dispose()` (`lib/src/api/classifiers/productivity_classifier.dart:283`) is:

```dart
Future<void> dispose() async {
  if (_disposed) return;
  _disposed = true;
  await _nativeReady;           // yields control
  ...
  await _channel.invokeMethod<void>(ClassifierMethods.dispose, {...});
}
```

The plan calls `_current!.dispose()` synchronously at the top of `build()` **without `await`**. After `_disposed = true`, the call yields at `await _nativeReady`. Control returns to `build()`, which then **synchronously** constructs the new classifier — whose constructor immediately invokes `ClassifierMethods.create` via `_channel.invokeMethod`. So the platform-channel call order is:

1. `create` for the new classifier (dispatched synchronously inside the constructor)
2. `dispose` for the old classifier (dispatched later from the resumed async function)

The plan's `_current.dispose()` trick is **not** "synchronous dispose-before-create" as the plan claims; it is "fire-and-forget dispose followed immediately by a synchronous create." On the platform side, the create lands first.

#### b) Even if the order were reversed, the SDK has no `Destroy` for classifiers

The Capsule SDK exposes `_Destroy` / `_Release` only for `clCDeviceLocator` and `clCDevice` (`official/iOS/CapsuleClient.framework/Headers/CDeviceLocator.h:84`, `CDevice.h:218`). `CProductivity.h`, `CCardio.h`, `CMEMS.h` only expose `_Create` / `_CreateWithIndividualData` — no destroy.

The iOS bridge documents this explicitly (`ios/Classes/classifiers/ProductivityBridge.swift:78`):

> "There is no `clCProductivity_Destroy` in the SDK — disposal is callback-only."

So `nativeDisposeProductivity` in `jni_productivity.cpp:254` only unsets the five `Set*Event` handlers and deletes JNI global refs — **it does not free the SDK's internal classifier-on-device registration.** Any subsequent `clCProductivity_Create(dev, &error)` on the same device is therefore guaranteed to hit the same "module already exists" path regardless of how many times the bridge "disposes."

#### c) The Kotlin bridge already enforces dispose-before-create

`ProductivityBridge.kt:51-58`, `MemsBridge.kt:39-46`, and the equivalent Cardio code already do:

```kotlin
fun create(deviceHandle: Long) {
    if (handle != 0L) dispose()
    ...
}
```

Adding another dispose-before-create on the Dart/Riverpod side is **redundant** with what the bridge already does. It does not change what the SDK sees: a second `clCProductivity_Create` for an already-registered device, which is exactly what aborts.

**Conclusion:** the patch from Tasks 1–3 will be applied cleanly, the unit will look "fixed" on the Dart side, and the SIGABRT will still happen the moment the user toggles the switch. The orchestrator's verification step will catch this regression — or worse, won't, because no test exercises a real Android device.

### 2. Root-cause work is missing from the plan

A correct plan needs to explore at least one of:

- **Why iOS doesn't crash but Android does.** Same SDK API, no destroy on either platform. Likely the iOS build of the SDK silently tolerates a second `Create` for the same device while the Android AAR aborts. This needs verification (read `official/Android/CapsuleService.aar` headers if extractable, or empirically test) before any fix is chosen.
- **Avoid recreating the classifier at all.** The simplest correct fix is to *not* tear down a working classifier when the toggle changes — instead, make the toggle take effect only on next session (e.g., disable the `Switch` once a classifier is alive, or require the user to stop+start the device to apply calibration changes). This is consistent with the SDK's lifecycle model (classifiers are owned by `Device` for its lifetime).
- **Tear down the device on toggle.** If hot-swapping calibration must work, the only SDK-legal path is to `Device.stop()` → release everything → `Device.start()` → create the classifier with the new args. This is a much larger change than the plan describes.
- **Add a one-shot scope key on `useCalibrationToggleProvider` rebuilds** that funnels through `Device.restart()` rather than just rebuilding the classifier provider.

None of these options is mentioned in the plan; the plan reaches for a Riverpod-shaped fix without confronting the SDK-shaped constraint.

### 3. The plan's stated trigger ordering contradicts Riverpod's documented behavior

Riverpod 2.x `Notifier` lifecycle runs all `ref.onDispose` callbacks registered during the previous `build()` **before** invoking the next `build()` when a watched dependency changes. So the premise "create runs before the previous instance's onDispose" is unlikely to be literally true. If the crash really happens on toggle, the more likely explanation is (1) above — the SDK fundamentally rejects a second `Create`, regardless of when the previous bridge's `dispose()` ran.

This matters because the plan is correcting a problem that may not exist, while ignoring the problem that does.

## Other Issues

### 4. Task 2 mis-describes the existing toggle guard

Task 2 says:

> "Do not change the existing `nfbData != null` toggle guard …"

The actual guard in `cardio_classifier_provider.dart:27` is `useCalibration && nfbData != null` (uses the shared `useCalibrationToggleProvider`). Task 1 describes the guard correctly; Task 2 should match. Not blocking on its own — just inconsistent wording — but the inconsistency suggests the file wasn't re-read carefully.

### 5. Task 4 documents a silent-degradation bug instead of fixing it

`jni_productivity.cpp:101` silently falls back from `_CreateWithIndividualData` to `_Create` when the symbol is missing. Result: when a user enables "Use NFB Calibration" on Android, the toggle has no behavioral effect — the calibration data is dropped on the JNI floor. Expanding the comment so future readers know this is fine; **leaving the silent fallback in place is not**. The bridge should either:

- Throw a `NOT_SUPPORTED` `clCError` so Dart can surface `UnsupportedError` and the example UI can hide the toggle on Android; or
- Have the Dart `withCalibration` factory check platform and refuse with a clear error on Android.

As written, Task 4 institutionalizes a user-visible feature lie. The plan should at minimum add a Dart-side platform check that throws on Android `withCalibration` until the symbol is exported, even if the JNI fallback stays for safety.

### 6. The `_current` field's null-clearing pattern is fragile

The proposed `ref.onDispose` callback does:

```dart
if (identical(_current, classifier)) _current = null;
```

But the line just above (`ref.onDispose(() { classifier.dispose(); })`) ensures `classifier.dispose()` is called. If `_current` was already reassigned during the next `build()` (which is the whole point of the new code), this `identical` check fails and `_current` stays pointing at the **new, live** classifier — which the surrounding teardown is about to dispose. This is harmless when the entire provider is being torn down (the whole notifier dies), but it's the opposite of what the comment in the existing code warns against:

> "Capture the local instance — do NOT read `state` inside the callback, as state may have been replaced by the time dispose fires."

The plan re-introduces exactly the foot-gun the existing comment was guarding against, just at the `_current` field. The cleanest variant is to drop the `_current = null` line from inside `onDispose` entirely (the GC will collect the disposed object once the new `build()` rotates).

### 7. No test or repro step is specified

The plan sets `Testing: no`. For a SIGABRT crash, "no test" is acceptable only if there is a documented **manual repro** the orchestrator can run on a device to verify the fix. There isn't. After implementation the orchestrator will have no way to confirm whether the crash is gone, especially given issue (1) above.

A bare-minimum acceptance criterion should be added: "Connect to a Headband on Android, start streaming, toggle Use NFB Calibration four times in 5 seconds; the app must not SIGABRT and the Productivity Indexes stream must continue emitting." Without this, "complete" is undefined.

## Suggested Changes Before Implementation

1. **Re-diagnose.** Confirm experimentally whether Riverpod's `onDispose` actually runs after the next build, or whether the SDK aborts on every second `Create`. Without this, the fix can't be designed correctly.
2. **Pick a strategy that respects the SDK lifecycle.** Either disable the toggle once a classifier exists, or implement Device restart on toggle change. Document the trade-off in the plan's Context section.
3. **Fix the Android-only silent fallback** (issue 5) instead of merely commenting on it. Either expose the failure to Dart or check platform in Dart and refuse.
4. **Add a manual repro acceptance criterion** so the orchestrator can verify the fix.
5. Tighten Task 2 wording to match the real guard (`useCalibration && nfbData != null`).

## Positive Notes

- The plan is focused and small, which is appropriate for a fix.
- The `_current` field idea is a reasonable Riverpod pattern — it's just being applied to a problem that isn't a Riverpod-ordering problem.
- The plan correctly identifies that the missing Android `CreateWithIndividualData` symbol is a relevant fact, even if it then handles it the wrong way.
- Files cited (`example/lib/providers/*`, `android/src/main/cpp/jni_productivity.cpp`) exist and the line references are accurate.
