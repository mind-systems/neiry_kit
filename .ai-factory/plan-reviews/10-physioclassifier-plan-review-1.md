# Plan Review: PhysioClassifier

**Plan file:** `.ai-factory/plans/10-physioclassifier.md`
**Files reviewed:** `lib/src/channel/channel_names.dart`, `lib/src/api/classifiers/nfb_classifier.dart`, `lib/neiry_kit.dart`, `lib/src/models/physio_states.dart`, `lib/src/models/nfb_user_state.dart`, `lib/src/api/device.dart`, `.ai-factory/notes/04-dart-api-classifiers.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** PASS — plan respects layered architecture (Dart API → channel constants → models), dependency direction is correct, file paths match the folder structure exactly.
- **RULES.md:** WARN — file does not exist; no project-level rules to gate against.
- **ROADMAP.md:** PASS — plan implements the `PhysioClassifier` milestone item verbatim; streams, methods, and factory signature match the roadmap spec.

## Critical Issues

None.

## Suggestions

None.

## Positive Notes

- **Precise pattern replication.** The plan correctly identifies every structural element of `NfbClassifier` (factory guard, `_nativeReady`/`_createError` lifecycle, `_eventStream` helper, `_checkNotDisposed`/`_checkReady` guards, idempotent `dispose`) and maps them onto PhysioClassifier with the right differences (no `calibration` constructor param, two post-creation methods instead).
- **Channel contract gap correctly identified.** The missing `physiologicalIndividualNfb` EventChannel ID is the only gap — all other required constants (`NeiryChannels.physiological`, `ClassifierMethods.create/startBaselineCalibration/importBaselines`, `NeiryArgs.serial/baselines`, and the three existing physio EventChannel IDs) already exist and are referenced by their real names.
- **Scope is tight.** Dart-only, 3 tasks, no native bridge work. Matches the roadmap's separation of Dart API milestones from iOS/Android bridge milestones.
- **Stream decode conventions are consistent with existing models.** `PhysiologicalStatesValue.fromMap` and `NfbUserState.fromMap` both exist and match the signatures the plan uses.
- **Naming of the new EventChannel (`physiologicalIndividualNfb`) leaves room for `productivityIndividualNfb`** which the ProductivityClassifier roadmap item will need — avoids a rename later.

PLAN_REVIEW_PASS
