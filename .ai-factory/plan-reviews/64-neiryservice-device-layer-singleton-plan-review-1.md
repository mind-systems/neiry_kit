# Plan Review: NeiryService — device layer singleton

**Plan file:** `.ai-factory/plans/64-neiryservice-device-layer-singleton.md`
**Risk Level:** 🟡 Medium

The plan is well-aligned with the codebase, references real APIs by their actual names, mirrors the established lifecycle patterns from `active_device_provider.dart`, and respects the roadmap promise (milestone 88 in `ROADMAP.md`). Two issues are worth fixing before implementation; the rest is solid.

## Context Gates

- **Architecture gate** — `.ai-factory/ARCHITECTURE.md` is present but does not yet describe a `services/` directory or a `NeiryService`. No conflict — this milestone introduces the concept, and later milestones (89–94) wire it in. WARN only: when the migration completes, ARCHITECTURE.md should be updated to mention `example/lib/services/`. Not a blocker for this milestone.
- **Rules gate** — no `.ai-factory/RULES.md` present. No violation possible.
- **Roadmap gate** — plan correctly references milestone 88 in `ROADMAP.md` (lines 87–94 of the roadmap describe the full refactor sequence) and is scoped strictly to the singleton creation; the deliberate "do not wire Riverpod / do not delete providers" boundary matches the roadmap split. ✓

## Critical Issues

### 1. The `NfbCalibrator` sentinel as proposed will not compile

Task 6 + Assumptions propose adding to `lib/src/api/nfb_calibrator.dart`:

```dart
const NfbCalibrator._handle();
static const NfbCalibrator handle = NfbCalibrator._handle();
```

But `NfbCalibrator` is declared `abstract final class` (`lib/src/api/nfb_calibrator.dart:37`). In Dart, **an `abstract` class cannot be instantiated even via a private const constructor** — the compiler rejects `const ClassName._ctor()` for abstract classes. The proposed SDK touch is therefore broken as written; the implementer will hit a static error.

Realistic fixes, in order of impact:

1. **Drop `abstract` from the declaration** — change `abstract final class NfbCalibrator` to `final class NfbCalibrator`. The class has no abstract members, so `abstract` is purely a "no public instances" marker — equivalent to keeping the constructor private. This is the smallest correct SDK touch.
2. **Use a private concrete subclass:**
   ```dart
   final class _NfbCalibratorHandle extends NfbCalibrator {
     const _NfbCalibratorHandle();
   }
   static const NfbCalibrator handle = _NfbCalibratorHandle();
   ```
   Slightly more code but preserves the `abstract` modifier.
3. **Adopt the documented fallback** (`bool get hasCalibrator => isConnected;`) and shift the `NfbCalibrator? get calibrator` contract to a later milestone. The plan already lists this as a fallback — promote it to the primary path if SDK changes are undesirable for this milestone.

Either way, update the Assumptions section so the implementer doesn't write code that fails to compile.

### 2. Task 1 omits the `_calibrator` field declaration

Task 1 enumerates the private mutable state to add (`_device`, `_disposed`, six classifier fields, `_nfbData`, `_activeSubscriptions`) but does not include `NfbCalibrator? _calibrator;`. Task 3 step 7 then assigns `_calibrator = NfbCalibrator.handle;`, and Task 4 instructs `_calibrator = null;`. Result: an implementer who walks the task list top-to-bottom will reference an undeclared field in Task 3 and have to backtrack.

Fix: add `NfbCalibrator? _calibrator;` to the private field list in Task 1 (gated on the sentinel approach being adopted in Task 6).

## Significant Issues

### 3. `flutter analyze` on a single file does not behave as Task 7 assumes

Task 7 says: "run `flutter analyze lib/services/neiry_service.dart`. Expect zero errors and zero warnings." `flutter analyze` accepts a path argument but it still requires `pub get` resolution for the package and effectively analyzes the dependency graph reachable from the entry — most importantly, it does **not** scope output to issues *in* the named file. The output may include diagnostics from the rest of `example/`.

Two concrete fixes:
- Use `dart analyze lib/services/neiry_service.dart` from `example/` — `dart analyze` honors the path argument and limits findings to the given file.
- Or change the success criterion to: "zero new errors introduced; existing example-app warnings unchanged." The plan should not claim "zero warnings" against the whole example app — milestone 88 leaves the old providers in place and there will be unresolved-import / dead-code lint candidates after subsequent milestones.

### 4. Double-listening on `Device` event streams — clarify expectations

`Device._startStateTracking()` (`lib/src/api/device.dart:136-152`) already subscribes internally to `connectionStateStream`, `modeChangedStream`, and `batteryStream` to maintain cached state. Task 3 step 6 instructs `NeiryService` to also subscribe to those same streams to feed the multiplexer controllers.

This is fine in practice — `EventChannel.receiveBroadcastStream` returns a *broadcast* stream and Flutter multiplexes listeners onto a single native subscription. The cached `late final` Stream fields in `Device` ensure both listeners share the same upstream. But the plan does not call this out, and a reader looking at the "Concurrent subscription warning" docstring on `Device` (which warns about *multiple Device instances*, not multiple listeners) could believe this is unsafe.

Fix: add a one-line note to Task 3 explaining that double-subscription is safe because `Device`'s stream getters return cached broadcast streams.

### 5. `disconnect()` waits for classifier disposal in series — acknowledge or parallelize

Task 4 instructs sequential `await _nfb?.dispose(); await _physio?.dispose(); …` for six classifiers. Each classifier's `dispose()` does `await _nativeReady` before invoking the native destroy method — so a fast Connect → Disconnect cycle waits for six native create round-trips on the platform thread before disconnect can complete. Worst case this could add a noticeable delay.

Acceptable for this milestone (the previous provider-based flow had the same characteristic via `ref.onDispose`), but worth either:
- Adding a brief comment in the plan acknowledging this, or
- Changing the instruction to `await Future.wait([_nfb?.dispose(), _physio?.dispose(), ...].nonNulls);` to dispose them concurrently.

## Minor Issues

### 6. `StreamController.broadcast(sync: false)` — `sync: false` is the default

The Assumptions section says "`StreamController.broadcast(sync: false)` is used." The default constructor `StreamController.broadcast()` already uses asynchronous delivery — `sync: false` is redundant but harmless. Not blocking; mentioning for completeness.

### 7. Empty stream semantics before `connect()`

Task 5 says: "All emit nothing when the corresponding classifier is null — naturally handled because the fan-in subscription only exists between `connect()` and `disconnect()`." Correct, but worth being explicit: a listener attached *before* `connect()` will not receive anything that arrived between the time the device's classifier began emitting and the time NeiryService's `_activeSubscriptions.add(...)` ran. This is the intended behavior (the plan acknowledges "subscribe before connect, receive after connect") but the implementer should not be surprised by the fact that early micro-events during `_device!.connect()` are missed if the classifier emits before NeiryService wires up its fan-in subscription. In practice the gap is microseconds and classifiers don't emit until streaming starts, so this is fine.

### 8. `_safeProductivityWithCalibration` private helper signature is not specified

Task 3 step 5 references a `_safeProductivityWithCalibration(_device!, nfbData)` helper but does not state the return type or fallback semantics. Implementer can copy the pattern from `ProductivityClassifierNotifier.build()` (`example/lib/providers/productivity_classifier_provider.dart:45-58`) — flag this so the implementer doesn't re-design it.

Suggested signature:
```dart
ProductivityClassifier _safeProductivityWithCalibration(Device device, IndividualNfbData data) {
  try {
    return ProductivityClassifier.withCalibration(device, data);
  } on UnsupportedError {
    return ProductivityClassifier(device);
  }
}
```

### 9. Connect failure path doesn't null out `_calibrator`

Task 3 step 4 cleans up `_device = null; _nfbData = null;` on connect failure, but if `_calibrator` was assigned earlier (Task 1 omitted the field, see issue 2), there's no rule for resetting it. With the field added per fix 2, the cleanup block should also set `_calibrator = null;` on failure for symmetry — although Task 3 step 7 only sets `_calibrator` on success, so realistically it's already null in the failure path. Worth one defensive line in case the implementation order changes.

### 10. Plan does not explicitly guard against `connect()` being called while another connect is in flight

`Already connected — call disconnect() first` (step 1) checks `isConnected`, which is `_device?.isConnected`. But between `_device = await _locator.createDevice(serial)` (step 3) and `await _device!.connect(...)` (step 4), `_device` is non-null but `isConnected` is false. A second `connect()` call during that window would create a second device handle, abandoning the first. Realistically this is a UI/Riverpod-layer concern (only one screen drives the service), and milestone 92 owns the call site discipline — but a `bool _connecting = false;` guard is a one-line precaution that future-proofs against accidental re-entry.

## Positive Notes

- The plan correctly preserves backward compatibility — existing providers and screens keep compiling, the file lives at a new path (`example/lib/services/neiry_service.dart`), and no deletions happen in this milestone. Matches the roadmap split (milestones 89–94 do the wiring/deletion).
- The cleanup pattern in Task 3 step 4 (try/catch device disposal on connect failure) mirrors `active_device_provider.dart:createAndConnect()` precisely, including the "swallow errors with `(_) {}`" idiom.
- The `device.isStarted` guard in `disconnect()` correctly references the fix landed in milestone 82 — avoids the SIGABRT regression from double-`stop()`.
- The decision to make `nfbData` a connect-time-only parameter (no runtime `setMemsCalibration()`-style mutators) is the right call given the SDK's "no Destroy" constraint already documented on the existing provider notifiers.
- Eager classifier construction at connect matches the milestone-80 fix for the Cardio/MEMS PPG-mode-switch issue.
- The plan respects the `Logging: minimal`, `Testing: no`, `Docs: no` settings consistently — no scope creep.
- Clean separation: NeiryService has no Flutter/Riverpod imports, keeping it plain-Dart and unit-testable later.
- Commit plan is reasonable: three logical units that each leave the file in a compilable state.

## Summary

The plan's architecture and task decomposition are correct. The blocking issue is the `NfbCalibrator` sentinel (Issue 1) which will not compile as currently written; the plan offers a fallback but the primary recommendation needs a code-level correction. Issue 2 (missing field declaration) is a small but high-friction omission. Issues 3–5 are clarifications that will save the implementer time. Address Issues 1 and 2 and the plan is ready to execute.
