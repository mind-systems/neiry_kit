# Plan Review: PhysioActionsNotifier and ProductivityActionsNotifier

**Plan:** `.ai-factory/plans/67-physioactionsnotifier-and-productivityactionsnotifier.md`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** OK. New files land in `example/lib/providers/`, which is the example-app Riverpod layer outside the plugin's `lib/src/` layered SDK boundary. The notifiers do not cross the public Dart API boundary or touch native code — alignment is clean.
- **Rules (`.ai-factory/RULES.md`):** Not present — non-blocking. WARN only.
- **Roadmap (`.ai-factory/ROADMAP.md`):** Item is line 91, "PhysioActionsNotifier and ProductivityActionsNotifier". Plan scope matches the roadmap item verbatim: SRP "commands only", screen migration explicitly deferred to roadmap line 93. ✅

## API & Codebase Verification

Cross-checked every external symbol the plan calls into:

| Symbol | Path | Status |
|---|---|---|
| `neiryServiceProvider` | `example/lib/providers/neiry_service_provider.dart:5` | ✅ exists, `Provider<NeiryService>` |
| `NeiryService.physioClassifier` getter | `services/neiry_service.dart:389` | ✅ returns `PhysioClassifier?` |
| `NeiryService.productivityClassifier` getter | `services/neiry_service.dart:392` | ✅ returns `ProductivityClassifier?` |
| `PhysioClassifier.startBaselineCalibration()` | `lib/src/api/classifiers/physio_classifier.dart:164` | ✅ `Future<void>`, no args |
| `PhysioClassifier.importBaselines(PhysiologicalStatesBaselines)` | `physio_classifier.dart:176` | ✅ typed model, matches plan |
| `ProductivityClassifier.startBaselineCalibration()` | `productivity_classifier.dart:256` | ✅ |
| `ProductivityClassifier.resetAccumulatedFatigue()` | `productivity_classifier.dart:281` | ✅ |
| `physioBaselinesProvider` | `classifier_stream_providers.dart:65` | ✅ `StateProvider<PhysiologicalStatesBaselines?>` |
| `PhysiologicalStatesBaselines` | re-exported via `package:neiry_kit/neiry_kit.dart` | ✅ already used by `classifiers_screen.dart:177` |

The plan's references to file paths, method signatures, types, and provider styles are all accurate. The Notifier pattern matches the existing `CalibrationTimerNotifier` (`calibration_timer_provider.dart:12`) and `ResistanceMapNotifier` (`stream_providers.dart:40`).

## Findings

### Suggestions (non-blocking)

1. **Imports may need `package:flutter_riverpod/legacy.dart`.**
   Task 1 writes `physioBaselinesProvider` via `ref.read(physioBaselinesProvider.notifier).state = baselines`. `StateProvider` and its `StateController` setter live in `flutter_riverpod/legacy.dart` (see `classifier_stream_providers.dart:2`). Depending on the Riverpod version, the consuming file may need to add the legacy import to access the `.state` setter without an analyzer warning. The plan should either add `package:flutter_riverpod/legacy.dart` to Task 1's import list or note that it may be required.

2. **"On success" wording is slightly ambiguous in Task 1.**
   The plan says: *"on success (i.e. when `physioClassifier` was non-null) write `baselines` into `physioBaselinesProvider`"*. The non-null check and "success" are not the same — `importBaselines` is async and can throw mid-call (e.g., classifier disposed concurrently, native error). The intended semantics are likely: `await classifier.importBaselines(b); ref.read(physioBaselinesProvider.notifier).state = b;` — so a throw skips the write. That is the right ordering, but the plan text should make it explicit (sequence the await before the state write, do not wrap in try/catch and swallow). Minor wording fix only.

3. **`Notifier<void>` is unusual but valid.**
   The build method becomes `void build() { /* empty */ }` — no return statement is needed because the return type is `void`. Worth a one-line note in the plan so the implementer doesn't try to `return null;`. Not a defect, just a clarity nit.

### Positive Notes

- Plan correctly identifies that `ProductivityClassifier.importBaselines` takes `Uint8List` (not `PhysiologicalStatesBaselines`) and explicitly excludes it from this milestone — avoids a foot-gun.
- Plan correctly insists on `ref.read` (not `watch`) for one-shot commands — matches Riverpod best practice and prevents accidental rebuilds.
- Screen migration is correctly deferred to roadmap item 93. The current screens still reference a non-existent `physioClassifierProvider` / `productivityClassifierProvider`; the plan acknowledges this is pre-existing and out of scope. ✅
- SRP boundary is clearly drawn: `PhysioActionsNotifier` is the only place that writes `physioBaselinesProvider`; `ProductivityActionsNotifier` writes nothing. Clean separation.
- File naming (`physio_actions_provider.dart`, `productivity_actions_provider.dart`) and provider naming (`physioActionsProvider`, `productivityActionsProvider`) follow the established lowerCamelCase, no-part-files convention in `example/lib/providers/`.

PLAN_REVIEW_PASS
