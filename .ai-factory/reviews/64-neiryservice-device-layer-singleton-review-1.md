# Code Review 1: NeiryService — device layer singleton

**Plan:** `.ai-factory/plans/64-neiryservice-device-layer-singleton.md`
**Files reviewed:**
- `example/lib/services/neiry_service.dart` (new, 369 lines)
- `lib/src/api/nfb_calibrator.dart` (modified — const constructor + `_NfbCalibratorHandle` + `handle` sentinel)

**Verdict:** Implementation matches the plan very closely. All seven tasks are reflected in the code, the SDK-side `NfbCalibrator` edit applies the const-constructor fix flagged by plan review 2, and stream types/classifier APIs all line up with the existing `lib/src/api/` surface. No critical or significant bugs found. A handful of minor robustness observations follow.

## Verification against the plan

- **Task 1**: ✓ Single import of `package:neiry_kit/neiry_kit.dart`; no Flutter/Riverpod imports. All 13 broadcast `StreamController`s eagerly initialised as field defaults. State fields (`_device`, `_disposed`, `_connecting`, six classifier nullables, `_nfbData`, `_calibrator`, `_activeSubscriptions`) all present and typed as specified. `_checkNotDisposed()` private guard exists; `isConnected`/`isStarted` derive from the underlying `Device` (`example/lib/services/neiry_service.dart:75-78`).
- **Task 2**: ✓ `scan()` is the one-liner the plan specifies (`neiry_service.dart:83-89`). `dispose()` re-entry guard is the single-flag form (`if (_disposed) return; _disposed = true;`) per plan review 2 issue 3 (`neiry_service.dart:281-299`). All 13 controllers are closed.
- **Task 3**: ✓ Connect signature matches; `_connecting` re-entry guard wraps the body in `try { … } finally { _connecting = false; }` (`neiry_service.dart:108-201`). Create-then-connect cleanup path mirrors `active_device_provider.dart:createAndConnect()` (`neiry_service.dart:114-123`). Classifier construction is eager, branches on `_nfbData`, and uses `_safeProductivityWithCalibration` (`neiry_service.dart:127-138`, helper at 359-368). `_calibrator = NfbCalibrator.handle` is set *before* the fan-in subscriptions, matching the updated step ordering in plan review 2 issue 6 (`neiry_service.dart:141`). All 13 fan-in subscriptions are wired with `onError` forwarding into the matching controllers (`neiry_service.dart:145-198`).
- **Task 4**: ✓ `disconnect()` follows the new order from plan review 2 issue 2: cancel subscriptions → dispose classifiers concurrently with `Future.wait` + per-call `.catchError` → device stop/disconnect/dispose → reset device-scoped fields (`neiry_service.dart:210-254`). `start()` propagates errors (`neiry_service.dart:261-265`). `stop()` propagates errors per plan review 2 issue 4 — no try/catch (`neiry_service.dart:270-274`).
- **Task 5**: ✓ All 13 stream getters present with the exact types listed in the plan. Stream types confirmed against the source classifiers:
  - `Stream<NfbUserState>` ← `NfbClassifier.stateStream` (`lib/src/api/classifiers/nfb_classifier.dart:128`)
  - `Stream<PhysiologicalStatesValue>` ← `PhysioClassifier.stateStream` (`lib/src/api/classifiers/physio_classifier.dart:127`)
  - `Stream<EmotionsStates>` ← `EmotionsClassifier.stateStream` (`lib/src/api/classifiers/emotions_classifier.dart:109`)
  - `Stream<CardioData>` ← `CardioClassifier.stateStream` (`lib/src/api/classifiers/cardio_classifier.dart:178`)
  - `Stream<List<MemsSample>>` ← `MEMSClassifier.memsStream` (`lib/src/api/classifiers/mems_classifier.dart:142`)
  - `Stream<ProductivityIndexes>` / `Stream<ProductivityMetrics>` ← `ProductivityClassifier.indexesStream`/`metricsStream` (`lib/src/api/classifiers/productivity_classifier.dart:206,213`)
  - Device streams (`connectionStateStream`, `modeChangedStream`, `eegStream`, `psdStream`, `resistanceStream`, `batteryStream`) all match `Device` (`lib/src/api/device.dart:240-279`).
  - Out-of-scope streams (`artifactsStream`, calibration progress/completion streams, `ppgStream`) correctly omitted.
- **Task 6**: ✓ `physioClassifier`/`productivityClassifier` getters exposed; the other four classifiers are stream-only (`neiry_service.dart:349-352`). `NfbCalibrator? get calibrator => _calibrator;` exposed at line 355. SDK touch matches plan review 2 issue 1 exactly: `const NfbCalibrator();` added on the parent (`nfb_calibrator.dart:41`); `static const NfbCalibrator handle = _NfbCalibratorHandle();` (`nfb_calibrator.dart:47`); `final class _NfbCalibratorHandle extends NfbCalibrator { const _NfbCalibratorHandle(); }` (`nfb_calibrator.dart:304-306`). `NfbCalibrator` is already exported via `lib/neiry_kit.dart:9`, so consumers reach the sentinel without a new export.
- **Task 7**: Verification step — no code change. (Reviewer note: I did not execute `dart analyze`; please run it as a separate check.)

The forward reference inside the same library file (`handle` references `_NfbCalibratorHandle` defined later in the file) is permitted by Dart — top-level/class-level declarations are resolved order-independently within a library.

## Minor observations

These are all beyond the plan's specified scope and are not blocking. Listing them for awareness.

### M1. `dispose()` is not robust to a failure inside `_locator.dispose()`

`neiry_service.dart:281-299` runs sequentially: `await disconnect();` → `await _locator.dispose();` → `await _<controller>.close();` × 13. If `_locator.dispose()` throws (e.g., the locator singleton was already disposed by another path), every controller below it stays open and any subscriber blocked on `await for (... in eegStream)` never receives `onDone`.

Two ways to harden this if it matters later:

- Close the controllers *before* disposing the locator (since the controllers are owned by `NeiryService` and don't depend on the locator).
- Wrap `await _locator.dispose();` in `try { … } catch (_) {}` for symmetry with the existing best-effort device teardown in `disconnect()`.

Not required by the plan. Practically unlikely because `NeiryService` is documented as singleton-style and owns the locator.

### M2. Stale `_nfbData` if `_locator.createDevice(serial)` throws

`connect()` sets `_nfbData = nfbData;` (`neiry_service.dart:110`) *before* the `createDevice` await (`neiry_service.dart:112`). If `createDevice` throws, control reaches the outer `finally` (clears `_connecting`) and rethrows — but `_nfbData` is left populated, while `_device` was never assigned. Subsequent state is self-correcting (the next `connect()` overwrites `_nfbData` first), so no leak in practice. Cosmetic.

Fix if desired: move `_nfbData = nfbData;` *after* the successful `createDevice`, or null it in the createDevice-failure path. Plan doesn't require either.

### M3. Partial-state leak if a classifier factory throws mid-construction

`connect()` constructs the six classifiers sequentially at `neiry_service.dart:127-138`. If `_physio = PhysioClassifier(_device!);` throws after `_nfb` was already assigned, `_nfb` is leaked unless the caller explicitly calls `disconnect()` afterwards (which would dispose `_nfb` and tear down the device — the cleanup path handles partial state correctly).

In practice the classifier factories only throw when `device.isConnected` is false, which cannot happen here because `Device.connect()` has just succeeded. The `Platform.isAndroid` `UnsupportedError` from `ProductivityClassifier.withCalibration` is already caught by `_safeProductivityWithCalibration`. So this is a theoretical concern, not a runtime one. Plan does not require defensive cleanup here.

### M4. Concurrent `disconnect()`/`dispose()` during in-flight `connect()` can NPE

The plan explicitly states (`Assumptions` section): *"`_connecting` is owned exclusively by `connect()`'s try/finally — `disconnect()` and `dispose()` never read or write it."* This is the documented contract.

Consequence: if `disconnect()` is called concurrently with `connect()` after `_device` has been assigned (line 112) but before classifier construction (line 127), `disconnect()` will null `_device` and dispose the Device while `connect()` is still awaiting `_device!.connect(...)`. When that await returns, the next `_device!` dereference at line 127 throws an NPE. The `connect()` caller sees a `Null check operator used on a null value` instead of a clean cancellation.

Per the plan this is intentional and the cost of the chosen design. Worth being aware of when wiring `NeiryService` into a Riverpod lifecycle in milestones 89–94 — ensure the consumer does not race `connect()` and `dispose()`.

## Cross-cutting sanity checks

- **Stream double-listen safety**: `Device.connectionStateStream`, `modeChangedStream`, `batteryStream` are already listened to internally by `Device._startStateTracking()` (`lib/src/api/device.dart:136-151`). `NeiryService` adds a second listener to each via fan-in. The `late final` cached broadcast streams plus `.map().where().cast()` preservation of broadcast-ness on `_modeChangedStream` mean Flutter multiplexes both listeners onto one native event-channel subscription — verified against `device.dart:61-83`. Safe, as the plan claims.
- **`Future.wait` over classifier `dispose().catchError((_) {})`**: each classifier's `dispose()` returns `Future<void>`; the chained `.catchError((_) {})` swallows any thrown error per-classifier so one failure can't abort the others. Correct shape.
- **`Device.stop()` returns `Future<bool>` but NeiryService discards the result**: confirmed at `neiry_service.dart:273` (`await _device!.stop();` — bool discarded). Matches plan's explicit decision.
- **`NeiryDeviceType.any`** is present at `lib/src/channel/enums.dart:15`. `scan()`'s default argument compiles.
- **Sentinel reachability**: `NfbCalibrator` is exported from `lib/neiry_kit.dart:9`; the `static const handle` is accessible from `example/` without a new export entry.
- **No Flutter/Riverpod imports in the service file**: confirmed — only `dart:async` and `package:neiry_kit/neiry_kit.dart`.
- **Plan task checkmarks**: tasks 1–7 are marked `[x]` in the plan, consistent with the implemented code.

## Recommendation

Ship as-is. The minor observations above are all defensive hardening suggestions outside the plan's scope; none of them block this milestone. If any are worth picking up, they fit naturally into milestone 89/90 when `NeiryService` is wired into Riverpod and concurrent lifecycle behaviour becomes more exercisable.
