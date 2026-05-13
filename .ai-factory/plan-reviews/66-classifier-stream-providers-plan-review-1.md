# Plan Review: 66-classifier-stream-providers

**Plan:** `.ai-factory/plans/66-classifier-stream-providers.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md** — not checked for boundary conflicts (this milestone stays inside `example/lib/` and adds three controllers to `NeiryService`, an existing module). No new cross-layer dependencies introduced.
- **RULES.md** — no `.ai-factory/RULES.md` present; nothing to enforce. **WARN**: optional file missing.
- **ROADMAP.md** — milestone #66 ("Classifier stream providers") is the current `[ ]` item under "Example app architecture refactor"; plan scope matches the roadmap description verbatim. Forward references to milestones #91 (`PhysioActionsNotifier` / `ProductivityActionsNotifier`), #92 (device/streams/main migration), #93 (classifiers/mems/productivity_cardio/calibration migration) are accurate and present in the roadmap.

## Codebase verification

Confirmed against current source:

| Plan claim | Verified in source |
|---|---|
| `_physioController`, `_emotionsController`, `_cardioController`, etc. controllers exist at `neiry_service.dart:48-65` | Yes — lines 48-65 match exactly |
| Fan-in block ends near `neiry_service.dart:199-202` with `_productivity!.metricsStream.listen(...)` | Yes — last entry in `_activeSubscriptions.addAll([...])` block, lines 199-202 |
| Controller `close()` calls in `dispose()` end with `_productivityMetricsController.close()` near line 304 | Yes |
| `PhysioClassifier.calibrationProgress` getter exists at `physio_classifier.dart:135` | Yes — line 135 |
| `ProductivityClassifier.calibrationProgress` getter exists at `productivity_classifier.dart:221` | Yes — line 221 |
| `CardioClassifier.ppgStream` getter exists | Yes — `cardio_classifier.dart:185` |
| `PpgData` is exported by `neiry_kit.dart` | Yes — line 28 |
| Calibration progress streams are safe to listen to before calibration starts | Yes — both `_calibrationProgress` getters only throw if `_createError != null`; cached event-channel streams are subscribed lazily and queue events until native is ready |
| Existing `stream_providers.dart` uses `ref.watch(neiryServiceProvider)` + plain `StreamProvider` pattern | Yes — established by milestone #65 |
| Legacy classifier providers' consumers are confined to four screens | Yes — grep confirms only `classifiers_screen.dart`, `productivity_cardio_screen.dart`, `mems_screen.dart`, `calibration_screen.dart` import any of the six legacy provider files |
| `physioBaselinesProvider` only consumed in `classifiers_screen.dart:84` | Yes; preserving it in the new file is correct |

## Architectural correctness

- The fan-in pattern proposed for `_cardioPpgController`, `_physioCalibrationProgressController`, `_productivityCalibrationProgressController` is identical to the established pattern for every other multiplexer controller — long-lived broadcast controllers opened at construction, fed from per-connection subscriptions, drained on `disconnect()`, closed only in `dispose()`. Consistent with the "broadcast controllers must stay open across reconnect" invariant called out at `neiry_service.dart:213-214`.
- The new `classifier_stream_providers.dart` reuses the `ref.watch(neiryServiceProvider)` + plain `StreamProvider` shape already established by milestone #65, eliminating per-classifier null-guards correctly — pre-connect subscribers simply receive no events from the multiplexer until `connect()` wires fan-in.
- `physioBaselinesProvider` is correctly kept as a `StateProvider` rather than being merged into `NeiryService`. It is a UI-side cache written by the (future) `PhysioActionsNotifier`, not data sourced from a native classifier — leaving it in the providers layer matches SRP.
- The deletion in Phase 3 is correctly time-boxed: the four expected-broken screens are exhaustively listed, the surviving identifiers will resolve once milestones #91–#93 land, and no in-scope screen edits are smuggled in.

## Potential issues

None blocking. A few small notes:

1. **Stream backpressure on `cardioPpgStream`** — PPG arrives at the device sample rate (commonly 50–125 Hz) in batches. The plan does not throttle the new `cardioPpgProvider`, which matches the existing `cardioPpgProvider` in `cardio_classifier_provider.dart:62-66` (also unthrottled). Consistent, but worth noting that consumers will continue to receive every native batch. Not in scope to change here.
2. **Phase 1 task 1.2 ordering** — the plan explicitly acknowledges that fan-in subscription order doesn't affect correctness and recommends grouping for readability. Fine.
3. **Doc references in new getters** — `[CardioClassifier]`, `[PhysioClassifier]`, `[ProductivityClassifier]` references in the new dartdoc comments resolve via the existing `package:neiry_kit/neiry_kit.dart` import in `neiry_service.dart:3`. No new imports needed.
4. **`physioCalibrationProgressStream` naming** — uses the suffix `Stream` to match every other public getter on `NeiryService` (`physioStream`, `emotionsStream`, etc.). Consistent.

## Positive notes

- Tasks are correctly ordered: Phase 1 extends the service first; Phase 2 depends on Task 1 and consumes the new streams; Phase 3 deletes legacy providers only after the replacement exists.
- File paths, line numbers, and getter names are all verified against current source.
- The plan explicitly enumerates the providers being intentionally omitted from the new file and routes them to future milestones with citations — eliminates the most common "missed something" failure mode.
- The "Expected `flutter analyze` errors" section turns post-deletion analyzer noise into a deliberate validation step instead of a debugging trap.
- Commit plan splits the service extension from the provider consolidation, keeping each commit reviewable in isolation.

PLAN_REVIEW_PASS
