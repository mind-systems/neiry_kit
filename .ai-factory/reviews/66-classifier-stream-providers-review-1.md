# Code Review: 66-classifier-stream-providers

**Plan:** `.ai-factory/plans/66-classifier-stream-providers.md`
**Scope reviewed:**
- `example/lib/services/neiry_service.dart` (modified)
- `example/lib/providers/classifier_stream_providers.dart` (new)
- Deletion of six legacy classifier provider files
- Cross-references in screen files that still import the deleted files

## Summary

All three plan tasks landed faithfully. The new broadcast controllers, fan-in subscriptions, getters, and dispose closures are wired correctly; the consolidated `classifier_stream_providers.dart` matches the planned API surface; the six legacy files are deleted. The expected `flutter analyze` damage (four screens with broken imports) is confined to the file list called out in the plan — no unexpected consumers were uncovered. No correctness, security, or runtime-safety findings.

## Findings

### Verified correctness items

1. **Broadcast controllers are open at construction and closed only in `dispose()`** — the new `_cardioPpgController`, `_physioCalibrationProgressController`, and `_productivityCalibrationProgressController` follow the long-lived pattern documented in the `NeiryService` class-level comment (`neiry_service.dart:12-14`). They survive across `disconnect → connect` cycles, so the new `StreamProvider`s safely watch them before the device is connected. (`neiry_service.dart:66-70`, `:322-324`)

2. **Fan-in subscriptions are added inside the single `_activeSubscriptions.addAll([...])` block** (`neiry_service.dart:192-219`), so they are torn down on `disconnect()` together with the rest — preventing leaks across reconnects. The classifier dispose order in `disconnect()` (`:236-251`) cancels all subscriptions before disposing classifiers, so no `add()` is called on a closed `late final` event stream.

3. **`PhysioClassifier.calibrationProgress` and `ProductivityClassifier.calibrationProgress` getters are safe to read at connect-time.** Both are `late final` lazy `_eventStream` wrappers around dedicated `EventChannel`s (`lib/src/api/classifiers/physio_classifier.dart:86-89,135-139`; `lib/src/api/classifiers/productivity_classifier.dart:151,221-225`). They emit nothing until calibration is started — matching the design assumption in `classifier_stream_providers.dart`. They also pass through `_checkNotDisposed`/`_checkReady`, but since the surrounding fan-in block already does this for `stateStream` reads of the same classifiers, no new failure mode is introduced.

4. **`CardioClassifier.ppgStream` exists and is broadcast-compatible** (`lib/src/api/classifiers/cardio_classifier.dart:135,185-189`). The single fan-in listener on it does not contend with screen listeners — only the new multiplexer controller is exposed to UI.

5. **Provider semantics match the planned shape:**
   - 8 data `StreamProvider`s, exactly the throttle policy in the milestone description (only MEMS throttled, 100 ms via `rxdart.throttleTime`). (`classifier_stream_providers.dart:9-49`)
   - 2 calibration progress `StreamProvider<double>`s. (`:52-59`)
   - 1 `StateProvider<PhysiologicalStatesBaselines?>` placeholder for the next milestone's `PhysioActionsNotifier`. (`:65-66`)
   - All providers use `ref.watch(neiryServiceProvider)`, matching the convention introduced by milestone #65 in `stream_providers.dart`. The service identity does not change at runtime; `watch` is harmless and parallels the surrounding code.

6. **Imports are correct.**
   - `flutter_riverpod/legacy.dart` is required for `StateProvider` in Riverpod 3 — already used elsewhere in this project (`device_scan_provider.dart`, removed `physio_classifier_provider.dart`). (`classifier_stream_providers.dart:2`)
   - `rxdart` is required for `.throttleTime` and is already a top-level dependency (consumed by `stream_providers.dart`). (`classifier_stream_providers.dart:4`)
   - `PpgData`, `PhysiologicalStatesBaselines`, `PhysiologicalStatesValue`, `EmotionsStates`, `CardioData`, `MemsSample`, `NfbUserState`, `ProductivityIndexes`, `ProductivityMetrics` are all part of the `neiry_kit` barrel (verified — used today by other screens/providers).

7. **Expected analyze-error surface matches the plan exactly.** The legacy files were deleted; the only remaining references to deleted symbols are:
   - `classifiers_screen.dart:6,8` — imports `emotions_classifier_provider.dart`, `physio_classifier_provider.dart`; uses `emotionsClassifierProvider`, `physioClassifierProvider`, `physioCalibratedProvider`, `physioBaselinesProvider`.
   - `productivity_cardio_screen.dart:6,9` — imports `cardio_classifier_provider.dart`, `productivity_classifier_provider.dart`; uses `useCalibrationToggleProvider`, `productivityClassifierProvider`, `cardioClassifierProvider`, `cardioCalibratedProvider`.
   - `mems_screen.dart:7` — imports `mems_classifier_provider.dart`; uses `useMemsCalibrationToggleProvider`, `memsClassifierProvider`.
   - `calibration_screen.dart:10` — imports `nfb_classifier_provider.dart`; uses `nfbClassifierProvider`.

   These are the four files listed in the plan's Task 3 acknowledgement and are explicitly punted to milestones #91/#92/#93. No surprise consumers detected. Note that `physioBaselinesProvider` (still referenced at `classifiers_screen.dart:84`) is resolved by the new file once the screen's import path is corrected — name and type are unchanged.

### Minor observations (non-blocking)

1. **Placement deviates from the plan's "next to other controllers" suggestion.** The new controllers, getters, and dispose closures were appended to the end of their respective blocks (`neiry_service.dart:66-70`, `:375-384`, `:322-324`) rather than grouped next to `_cardioController`, the existing cardio/physio/productivity getters, and `_productivityMetricsController.close()`. The plan called this out as a readability suggestion only ("Order inside the list does not affect correctness"). No runtime impact; future readers will see "newer additions at the bottom" rather than source-grouped.

2. **Subtle behavior change vs. the legacy providers (intentional and consistent with milestone #65).** Old `*StateProvider`s returned `Stream.empty()` when the classifier was null, so on disconnect Riverpod rebuilt the provider with a fresh empty stream. New providers stay subscribed to the long-lived broadcast controller across disconnect; once data has been emitted, `AsyncValue` retains the last value until the next emission. Screens use `.when` / `.whenOrNull` and handle loading uniformly, so UX should be equivalent — but if any screen relied on `AsyncValue` resetting on disconnect (e.g., to clear stale readings), that semantic is gone. Worth verifying during the #93 screen migration; no action needed in this milestone.

3. **Pre-existing latent issue, not introduced here:** if `PhysioClassifier`/`ProductivityClassifier` construction sets `_createError`, the `calibrationProgress`/`stateStream` getters throw `StateError` from `_checkReady()`. Reading either getter inside the `_activeSubscriptions.addAll([...])` list literal would abort the entire fan-in setup synchronously while classifiers are already constructed. The existing `stateStream` reads at `:180-211` already share this risk, so no new attack surface — but the failure mode now spans two additional streams per classifier (calibration progress on physio + productivity, ppg on cardio). Out of scope to fix here; flag for awareness.

## Verdict

The diff implements the plan correctly, leaves no leaks, and respects the documented "screens stay broken until #91–#93" scope boundary. No code changes requested.

REVIEW_PASS
