# Plan Review 3: NeiryService — device layer singleton

**Plan file:** `.ai-factory/plans/64-neiryservice-device-layer-singleton.md`
**Risk Level:** 🟢 Low

The third iteration of the plan resolves the lone blocker from review 2 (the `const _NfbCalibratorHandle()` constructor not compiling) by explicitly requiring **two coordinated edits** in `lib/src/api/nfb_calibrator.dart`: a `const NfbCalibrator();` constructor on the parent abstract class and the private subclass + `static const handle` sentinel. The plan also captures the two fallback escape hatches (drop `const` from the sentinel, or drop the getter entirely) so the implementer has a recovery path if the SDK touch is rejected at code-review time.

All other v2 nudges have been folded in: classifier dispose now runs **before** `device.disconnect()` / `device.dispose()`; the dispose re-entry guard wording is collapsed to a single `if (_disposed) return;`; `stop()` failure semantics are now stated explicitly ("errors propagate"); `isStarted`/`isConnected` truth-source note is in Assumptions; the `_modeChangedStream` broadcast-ness explanation is in Assumptions; `_connecting` ownership note is in Assumptions; the `memsStream` throttling deferral mentions the future provider/consumer; and commit 3 explicitly calls out that it touches both `lib/` and `example/`.

## Context Gates

- **Architecture gate** — `.ai-factory/ARCHITECTURE.md` is present but does not yet describe `example/lib/services/`. **WARN** only; introducing the directory is the entire point of this milestone, and ARCHITECTURE.md is updated in a later milestone in the 88–94 chain. Not a blocker.
- **Rules gate** — no `.ai-factory/RULES.md`. No violation possible.
- **Roadmap gate** — plan correctly scopes itself to the active roadmap milestone (NeiryService device layer singleton) and explicitly defers Riverpod wiring/screen migration to milestones 89–94. ✓
- **Skill-context gate** — no `.ai-factory/skill-context/aif-review/SKILL.md`. No project-specific override rules apply.

## Critical Issues

None.

## Significant Issues

None blocking. The plan is ready to execute as written.

## Minor Issues / Suggestions

### 1. Step 5 has no failure containment if a classifier constructor throws after step 4 succeeds

`NfbClassifier`'s factory (`lib/src/api/classifiers/nfb_classifier.dart:44-49`) throws `StateError` when the device is not connected — the plan calls these factories after `await _device!.connect(...)` returns, so `_connected = true` by then and the `not connected` branch will not fire on the happy path. However, the construction block in Task 3 step 5 is **not wrapped in try/catch**. If any classifier constructor throws for an unanticipated reason (e.g. a future SDK change, or a synchronous platform-channel throw on the `createCalibrated` invocation path before `catchError` attaches), `_device` and any earlier `_<classifier>` fields will be left non-null and the caller will see the exception without an automatic rollback.

The probability is low because the existing factories defer all native work via `_nativeReady` (errors land on `_createError`, not on the constructor return path), but the plan could close the loop with one line: "If any classifier constructor throws unexpectedly, the caller is expected to call `disconnect()` to clean up; partial state is not auto-rolled-back in this milestone." Optional; current behavior matches the per-provider construction pattern in `example/lib/providers/` today.

### 2. `Device.disconnect()` calls `_checkNotDisposed()` — the catch-all in disconnect step 3 already handles this, but a one-line note would help

Task 4 step 3 wraps each `_device!.stop()` / `disconnect()` / `dispose()` in `try { … } catch (_) {}`. That correctly swallows the `StateError('Device has been disposed')` that `_device!.disconnect()` would throw if `_device!.dispose()` somehow ran first — but the natural reading of the order (`stop → disconnect → dispose`) makes the swallow look defensive-only. Worth a one-line comment in the plan: "The catch in each step also covers the case where `_device` was disposed externally (e.g. native disconnect event followed by another caller racing dispose)." Pure documentation polish.

### 3. `dispose()` controller-close loop is elided

Task 2's `dispose()` body uses `// … close every multiplexer controller in turn …` as a placeholder. There are 13 multiplexer controllers (matching Task 5). For an implementer who is mechanically translating the plan into code, an explicit list of the 13 `await _xController.close();` calls (or at least the explicit count + naming convention) would prevent off-by-one omissions. The pairing rule "every getter in Task 5 → one `close()` in `dispose()`" is implicit and can be missed.

A one-line annotation like *"close all 13 controllers — names mirror the getter list in Task 5, e.g. `_connectionStateController`, `_modeController`, `_eegController`, …"* would close the gap. Optional.

### 4. `dispose()` ordering inside the controllers vs disconnect

`dispose()` calls `await disconnect()` (which fans events to controllers via subscriptions that are cancelled in disconnect step 1) **before** closing the controllers. After `_activeSubscriptions` is cancelled inside `disconnect()`, no further events flow, so closing afterward is clean. ✓ This is correct as written — flagging only to confirm the sequencing was deliberate.

### 5. `_locator.dispose()` placement

`dispose()` awaits `disconnect()` then `_locator.dispose()` then closes controllers. `DeviceLocator.dispose()` (`lib/src/api/device_locator.dart:214`) cancels any in-flight scan stream. The plan implicitly assumes nothing awaits `scan()`'s emitted stream past `dispose()` — which is consistent with how `scan()` is designed (consumers cancel their subscriptions). No issue, but if `scan()` is in flight at the moment `dispose()` is called, the scan stream subscriber sees an abrupt close. This matches current behavior elsewhere and is intentional.

## Codebase verification

Spot-checked against `lib/`:

- `NfbCalibrator` is `abstract final class` with no constructor (`lib/src/api/nfb_calibrator.dart:37`) — plan's coordinated-edit instruction is necessary and correct.
- `NfbClassifier`'s factory accepts `calibration:` named arg (`lib/src/api/classifiers/nfb_classifier.dart:44`) — matches plan task 3 step 5.
- `ProductivityClassifier.withCalibration` throws `UnsupportedError` on Android (`lib/src/api/classifiers/productivity_classifier.dart:76-87`) — matches the `_safeProductivityWithCalibration` helper pattern.
- `CardioClassifier.withCalibration`, `MEMSClassifier.withCalibration` exist with `(Device, IndividualNfbData)` signatures — matches plan task 3 step 5.
- `Device.connect()`, `disconnect()`, `start()`, `stop() → Future<bool>`, `dispose()` all match plan call shapes; `stop()`'s `Future<bool>` return is correctly identified as discardable via `await`.
- `Device._modeChangedStream` is the inline `.map().where().cast()` chain at `lib/src/api/device.dart:67-83`. `.map`/`.where`/`.cast` preserve broadcast-ness on a `receiveBroadcastStream` source — plan's Assumptions block is accurate.
- `Device._startStateTracking()` attaches internal listeners to `_connectionStateStream`, `_modeChangedStream`, and `_batteryStream` (`lib/src/api/device.dart:136-152`). The plan's "double-subscribe is safe" note is consistent with this.
- `NfbCalibrator` is re-exported via `lib/neiry_kit.dart` — `NfbCalibrator.handle` is reachable from `example/` without a new export line, matching Task 6's claim.
- `active_device_provider.createAndConnect()` (`example/lib/providers/active_device_provider.dart:19-48`) and `disconnectAndDispose()` (line 51-65) match the patterns the plan cites for connect-failure cleanup and teardown order.
- Stream types in Task 5 (`PhysiologicalStatesValue`, `EmotionsStates`, `CardioData`, `List<MemsSample>`, `NfbUserState`, `ProductivityIndexes`, `ProductivityMetrics`) match the classifier source files.
- `memsProvider` in `example/lib/providers/stream_providers.dart` applies `throttleTime(100ms)` — plan correctly defers throttling to the consumer.

## Positive Notes

- The single remaining v2 blocker (const constructor) is now explicitly addressed in both the Assumptions section and Task 6, with the parent-class const-constructor edit called out as a required prerequisite for the const sentinel.
- Both fallback paths (A: drop `const`; B: drop the getter entirely, ship `bool get hasCalibrator`) are documented inside the plan so the implementer does not have to invent a recovery path mid-implementation if the SDK touch is rejected.
- Disconnect order now matches the established Riverpod teardown order — classifiers first, then device — which mirrors how `active_device_provider.disconnectAndDispose()` and the per-classifier `ref.onDispose` hooks interact today.
- The `_checkNotDisposed()` placement is explicitly documented as *not* called in `disconnect()` / `stop()`, with the rationale stated inline (would deadlock the dispose path). This prevents a defensive implementer from over-applying the guard.
- The `_connecting` re-entry guard owns its lifecycle entirely inside `connect()`'s `try/finally`, with the ownership rule now in Assumptions — disconnect/dispose are explicitly forbidden from touching it.
- `stop()` failure semantics are no longer ambiguous — errors propagate to the caller, matching `start()`'s contract.
- Commit 3 is explicitly described as touching two files in different packages (`lib/src/api/nfb_calibrator.dart` + `example/lib/services/neiry_service.dart`), with the rationale for keeping them in one commit (avoid a defined-but-unused symbol).
- The plan still forbids `setMemsCalibration()` / `setProductivityCalibration()`-style runtime reconfiguration, matching the SDK's create-only model and preventing the Android "module already exists" crash from milestone 56.
- The plan still preserves backwards compatibility — no existing provider/screen is deleted in this milestone — keeping the example app compilable in parallel during the 89–94 migration.

## Summary

The blocker from review 2 is resolved. All four "significant issues" from review 2 are addressed. The minor issues listed above are documentation polish only — they would help an implementer translate the plan mechanically without backtracking, but none of them change the design or risk-level.

The plan is internally consistent, the codebase assumptions check out against `lib/` and `example/`, the SDK touch is minimal and isolated to a single file, the commit plan keeps each commit independently compilable, and the fallback paths are preserved as escape hatches. Ready to execute.

PLAN_REVIEW_PASS
