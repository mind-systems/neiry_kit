# Plan Review 2: NeiryService — device layer singleton

**Plan file:** `.ai-factory/plans/64-neiryservice-device-layer-singleton.md`
**Risk Level:** 🟡 Medium → very close to 🟢 Low

The second iteration of the plan resolves the bulk of the issues raised in review 1 — the missing `_calibrator` field is added, `dart analyze` replaces `flutter analyze`, the double-listen note is in place, classifier disposal is now parallel, the `_safeProductivityWithCalibration` helper is fully spelled out, the connect-failure path nulls `_calibrator`, and a `_connecting` re-entry guard wraps the connect lifecycle in `try/finally`. The plan is also internally consistent with the codebase: stream types, classifier factories, lifecycle ordering, and barrel exports all match what is actually in `lib/`. One concrete compile hazard from review 1 is still not fully resolved, and a small set of clarifications would save the implementer from minor backtracking.

## Context Gates

- **Architecture gate** — `.ai-factory/ARCHITECTURE.md` is present but does not yet describe `example/lib/services/`. WARN only; the milestone is the introduction point and ARCHITECTURE.md is updated in a later milestone in the 88–94 chain. Not a blocker.
- **Rules gate** — no `.ai-factory/RULES.md`. No violation possible.
- **Roadmap gate** — plan correctly scopes itself to roadmap milestone 88 ("NeiryService: device layer singleton") and explicitly defers Riverpod wiring/screen migration to milestones 89–94. ✓

## Critical Issues

### 1. The `_NfbCalibratorHandle` const constructor still will not compile as written

The plan v2 adopts option 2 from review 1 (private concrete subclass):

```dart
final class _NfbCalibratorHandle extends NfbCalibrator {
  const _NfbCalibratorHandle();
}
// inside abstract final class NfbCalibrator { … }:
static const NfbCalibrator handle = _NfbCalibratorHandle();
```

But `NfbCalibrator` (`lib/src/api/nfb_calibrator.dart:37`) declares **no constructor at all** — it has only static members, so Dart synthesises the default unnamed constructor `NfbCalibrator()`, which is **non-const**. A const generative constructor in a subclass must invoke a const constructor in the superclass (Dart language spec: "If c has explicit super constructor invocations… If c invokes K's default constructor, K must have a const default constructor."). The implementer will therefore get:

```
The constructor 'NfbCalibrator' isn't a const constructor.
```

on `const _NfbCalibratorHandle()`.

The fix is one line — declare a const constructor on `NfbCalibrator`:

```dart
abstract final class NfbCalibrator {
  const NfbCalibrator();
  // … existing static members unchanged …
}
```

This is compatible with `abstract` (abstract classes may have const constructors that are only invoked from concrete subclasses) and does not change the public surface since no caller can construct the class directly anyway (private subclass only).

Update Task 6 / the Assumptions section to call this out explicitly. As written, the plan tells the implementer to add the subclass + sentinel but does not mention the parent-class const constructor, and the natural cut-and-paste reading will not compile.

Alternatives if the SDK touch should remain even smaller:

- Drop `const` from the sentinel: `static final NfbCalibrator handle = _NfbCalibratorHandle();` — works without any change to `NfbCalibrator` (and without `const _NfbCalibratorHandle()`).
- Apply the documented fallback (`bool get hasCalibrator => isConnected;`) and defer the full getter to milestone 94.

Either of these would also resolve the issue; the plan already lists the third option but does not list the second.

## Significant Issues

### 2. `disconnect()` ordering: classifier dispose happens after `device.dispose()`

Task 4 orders the disconnect sequence as:

1. Cancel `_activeSubscriptions`.
2. `device.stop()` (guarded on `isStarted`).
3. `device.disconnect()`.
4. `device.dispose()`.
5. `Future.wait([...classifier.dispose()...])`.

Each classifier's `dispose()` invokes a native destroy method which `await`s `_nativeReady` first — i.e. it makes a platform-channel call that is logically scoped to the device. By the time step 5 runs, `device.dispose()` has already torn down the native device handle (step 4). On the native side this may be benign (the bridges are presumably defensive), but it's the opposite order from `active_device_provider.dart` + the per-classifier providers today, where each classifier's `ref.onDispose` fires before `disconnectAndDispose()` calls `device.dispose()` (because Riverpod tears down dependent providers first).

Recommendation: dispose classifiers **before** `device.disconnect()` / `device.dispose()`, mirroring the existing Riverpod teardown order. A safer sequence:

1. Cancel `_activeSubscriptions`.
2. `Future.wait` over classifier `dispose()` calls.
3. Null out classifier fields.
4. `device.stop()` (guarded on `isStarted`), `device.disconnect()`, `device.dispose()`.
5. Null out `_device`, `_nfbData`, `_calibrator`.

If the current order is intentional (e.g. because the native side requires the device alive to drain queued events before destroy), the plan should say so — otherwise the implementer should follow the established Riverpod ordering.

### 3. `dispose()` re-entry guard is described twice with conflicting wording

Task 2 says: *"Make `dispose()` idempotent — guard on `if (_disposed) return;` at the top using a separate `bool _disposed` check before flipping the flag (so re-entry from `disconnect()` paths is safe)."*

Task 1 has already declared `_disposed`, and `dispose()` is described as setting `_disposed = true` before awaiting `disconnect()`. The phrase "using a separate `bool _disposed` check before flipping the flag" reads as if there are *two* `_disposed` flags. The intent is just: `if (_disposed) return; _disposed = true; …`. Simplify the wording so the implementer doesn't introduce a redundant secondary flag.

Also worth flagging explicitly: `_checkNotDisposed()` is called at the top of `scan()` and `connect()`, but **not** at the top of `disconnect()` or `stop()`, because those are no-ops when there is no device. The plan does not contradict this, but stating it inline near each method (or noting it in Task 4) would prevent a defensive implementer from adding a `_checkNotDisposed()` to `disconnect()` and then having `dispose()` deadlock when it awaits a `disconnect()` that throws.

### 4. `stop()` failure semantics are unspecified

Task 4 ends with: *"`stop()`: `_checkNotDisposed(); if (_device == null) return; await _device!.stop();` — return type `Future<void>` (callers in milestone 92 read `device.isStarted` via NeiryService getter; they do not consume the bool return of `Device.stop`)."*

Two small gaps:

- The plan does not say whether errors from `Device.stop()` should propagate to the caller or be swallowed. Milestone 82's fix (`active_device_provider.disconnectAndDispose()`) swallows them with `try { … } catch (_) {}`. The `start()` method propagates errors (per the spec in Task 4: no try/catch). Be explicit: which behavior do you want for `stop()`? The most defensible answer is to propagate (so a UI Start button can show "stop failed"), but the plan should say so.
- The `isStarted` getter returns `_device?.isStarted ?? false`. After a successful `stop()`, `Device._started` flips to `false` internally, so the getter behaves correctly. Worth a one-line note in Task 5 confirming that `isConnected`/`isStarted` derive their truth from the underlying `Device` and don't need separate caching in `NeiryService`.

## Minor Issues

### 5. `_loggedUnknownModeCodes` / mode stream caveat

`Device._modeChangedStream` (`lib/src/api/device.dart:67-83`) is **not** built via `_eventStream()` — it has an inline `.map().where().cast()` chain. Whether the resulting stream is still a broadcast stream is technically a property of how `.map`/`.where`/`.cast` interact with the source `receiveBroadcastStream`. In practice they preserve broadcast-ness (Dart's `_MapStream.isBroadcast` returns the source's), and `Device` already attaches an internal listener via `_startStateTracking()`, so adding a second listener in NeiryService is fine. Not a blocker — but the "double-listen is safe because `Device` exposes cached broadcast streams" note in Task 3 step 6 / Assumptions is only true *because* `.map`/`.where` on a broadcast stream are also broadcast. Worth one extra line if precision matters.

### 6. Task 3 step 6 — order between subscribe and step 7

Task 3 sets `_calibrator = NfbCalibrator.handle;` in step 7, *after* the fan-in subscriptions in step 6. The placement is fine in success-path terms, but the failure path described in step 4 nulls `_calibrator` regardless. Since `_calibrator` is only assigned in step 7, the defensive `_calibrator = null;` in step 4's catch is, as the plan itself notes, a no-op. Consider either removing the defensive line (less noise) or moving the calibrator assignment earlier (before step 6) so the defensive null actually has purpose. The current state is harmless; just slightly inconsistent.

### 7. `disconnect()` does not reset `_connecting`

`_connecting` is set in Task 3 step 1 and cleared in a `finally` block inside `connect()`. `disconnect()` does not touch `_connecting`, which is correct (connect's `finally` owns that flag). But if `connect()` is ever modified to schedule a fire-and-forget cleanup that calls `disconnect()` while `_connecting` is true, the flag could leak. Add a one-line note: "`_connecting` is owned exclusively by `connect()`'s try/finally — `disconnect()` and `dispose()` never touch it." Cheap insurance against future refactors.

### 8. Task 5 wording around throttling for `memsStream`

Task 5 says: *"`memsStream` (`Stream<List<MemsSample>>` — unthrottled here; throttling stays in the consumer provider as `memsProvider` does today)."* The current `mems_classifier_provider.dart` is the source of truth for this. After milestone 88 the provider survives but is no longer the canonical path once 89–94 land. The plan correctly leaves the throttling out of NeiryService, but adding "throttling will move to a future provider/consumer wrapping NeiryService" makes the intent unambiguous.

### 9. Commit plan doesn't explicitly tie commit 3 to the SDK file

Commit 3 is described as "Expose NeiryService data streams, classifier getters, and calibrator sentinel" — that commit also touches `lib/src/api/nfb_calibrator.dart`. The plan should note that commit 3 modifies *two* files (one in the SDK, one in `example/`) so the implementer doesn't accidentally split them. Alternatively, the SDK touch could be its own commit between commits 2 and 3 to keep the SDK change isolated for `lib/` reviewers.

## Positive Notes

- Every issue from review 1 (`flutter analyze` scope, missing `_calibrator` field, sequential disposal, sentinel approach, `sync:` flag, empty-stream semantics, helper signature, calibrator cleanup symmetry, re-entry guard) is addressed in v2.
- Stream type references in Task 5 match the actual signatures in `lib/src/api/classifiers/*.dart` — `PhysiologicalStatesValue`, `EmotionsStates`, `CardioData`, `List<MemsSample>`, `NfbUserState`, `ProductivityIndexes`, `ProductivityMetrics`. No fabrication.
- Eager classifier construction at `connect()` correctly addresses the milestone-80 PPG-mode-switch issue and matches the documented "no Destroy" SDK constraint.
- Connect failure path mirrors `active_device_provider.createAndConnect()`'s try/catch/swallow idiom exactly, including the `device.dispose()` then `device = null` cleanup order.
- The `Future.wait` with `.catchError((_) {})` per classifier in `disconnect()` is the right shape — disposing concurrently while preventing one failure from aborting the others.
- The fallback (`bool get hasCalibrator`) is preserved as a recorded option, which gives the implementer an escape hatch if the SDK touch is rejected during code review.
- The plan explicitly forbids `setMemsCalibration()` / `setProductivityCalibration()`-style mutators, which matches the SDK's create-only model and prevents Android's `module already exists` crash from milestone 56.
- Backwards compatibility is intact: no existing provider or screen is deleted, the new file lives at a fresh path, and `dart analyze` is scoped to the new file only.
- Commit plan keeps each commit compilable, which matters for `git bisect` against later milestones.

## Summary

The plan v2 is materially better than v1 and is one tweak away from clean. The single remaining blocker is the `const _NfbCalibratorHandle()` constructor — without adding `const NfbCalibrator();` to the parent class, the proposed SDK touch will fail to compile. Issues 2–4 are clarifications or ordering nudges that will help the implementer; issues 5–9 are cosmetic. Fix issue 1 and the plan is ready to execute.