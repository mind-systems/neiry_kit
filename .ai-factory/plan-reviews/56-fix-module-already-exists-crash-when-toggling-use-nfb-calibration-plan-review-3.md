# Plan Review: 56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration (v3)

**Plan file:** `.ai-factory/plans/56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration.md`
**Files reviewed:** plan + `productivity_classifier_provider.dart`, `cardio_classifier_provider.dart`, `mems_classifier_provider.dart`, `nfb_classifier_provider.dart`, `device_state_providers.dart`, `productivity_cardio_screen.dart`, `mems_screen.dart`, `lib/src/api/classifiers/productivity_classifier.dart`, `android/src/main/cpp/jni_productivity.cpp`, `android/src/main/cpp/jni_cardio.cpp`, `official/iOS/CapsuleClient.framework/Headers/CError.h`, `nfb_calibration_provider.dart`, `calibration_provider.dart`, v2 review.
**Risk Level:** 🟢 Low — every v2 concern is addressed; the plan is internally consistent and matches the codebase.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** present. Changes stay within the example app, the plugin's Dart `ProductivityClassifier`, and the Android JNI bridge — no module boundary is crossed. PASS.
- **Rules (`.ai-factory/RULES.md`):** not present. SKIP.
- **Roadmap (`.ai-factory/ROADMAP.md`):** present. As noted in v2, the existing roadmap entry still references the previous (rejected) dispose-before-create strategy; not a blocker. WARN — non-blocking.
- **Skill-context (`.ai-factory/skill-context/`):** not present. SKIP.

## v2 Issue Resolution

Every issue raised by review v2 is now addressed:

| v2 Issue | v3 Resolution |
|---|---|
| 1. `nfbCalibrationProvider` still `ref.watch`, so calibration import reproduces SIGABRT | **Resolved.** New Phase 2 / Task 3 switches all three notifiers to `ref.read(nfbCalibrationProvider)`, matching the pattern already in `nfb_classifier_provider.dart:22`. |
| 2a. `clCError.message` is `char[256]` — assignment won't compile | **Resolved.** Task 4 explicitly uses `snprintf(error.message, sizeof(error.message), "...")` and calls out the buffer-size constraint. |
| 2b. `clCError_Unknown` is wrong-shape for "symbol not in this build" | **Resolved.** Task 4 specifies `clCError_ModuleIsNotSupported` (verified at `CError.h:18`) with the correct semantic justification. |
| 3. Acceptance criterion vs Task 5 mismatch (subtitle vs silent fallback) | **Resolved.** Acceptance criterion (lines 22–23) now picks the silent-fallback path explicitly: "the `ProductivityClassifierNotifier` catches the `UnsupportedError` and falls back to the plain `ProductivityClassifier(device)`." The "explanatory subtitle" wording is gone. |
| 4. Missing `debugPrint` import | **Resolved.** Task 6 calls out: `import 'package:flutter/foundation.dart' show debugPrint;` with the explicit note that it is not transitively imported. |
| 5. `try`/`catch` scope ambiguity | **Resolved.** Task 6 spells out the exact shape with `try` wrapping only the `withCalibration` call, plus the line "The `try` must wrap **only** the calibrated factory call — not the `else` branch and not the `ref.onDispose(...)` block that follows." |
| 6. Unacknowledged iOS UX regression | **Resolved.** Context paragraph 1 (line 11) now states: "On iOS this is a deliberate UX regression: today iOS users *can* hot-swap calibration mid-stream because the iOS framework swallows the second `_Create`; after this change they no longer can." |
| 7. Unused JNI parameters under `-Werror` | **Resolved.** Task 4 instructs the implementer to silence each parameter with `[[maybe_unused]]` or `(void)param;` and lists the exact parameters to cover. |
| 8. Verbose TODO comment | **Resolved.** Task 4 specifies a single-line `// TODO(neiry-aar): restore _CreateWithIndividualData path when the AAR exports it.` |
| 9. Manual repro missing calibration-import-while-started path | **Resolved.** Acceptance criterion bullet 3 (line 21) adds: "With the device **already started**, navigating to the Calibration tab and importing a calibration from file (or running `startQuick`) must not SIGABRT — the Productivity, Cardio and MEMS streams must keep emitting from the originally-created classifiers." |

## Verification Against Codebase

- `productivity_classifier_provider.dart:31`, `cardio_classifier_provider.dart:23`, `mems_classifier_provider.dart:30` — confirmed: all three currently `ref.watch(nfbCalibrationProvider)`. Task 3 correctly targets exactly these three lines.
- `nfb_classifier_provider.dart:22` — confirmed: already uses `ref.read(nfbCalibrationProvider)`. The plan's reference pattern is accurate.
- `calibration_provider.dart:121` (`importFromFile`) and `:141` (`_writeToSharedProvider`) — confirmed: both mutate `nfbCalibrationProvider.notifier.state`. Phase 2 correctly identifies these as the residual SIGABRT trigger.
- `productivity_cardio_screen.dart:74–80` and `mems_screen.dart:37–44` — confirmed: both `SwitchListTile`s already have the `nfbData == null ? null : (val) {...}` shape that Phase 1 extends with the streaming gate.
- `device_state_providers.dart` exports `deviceUiStateProvider` and `DeviceUiState.started` — confirmed at lines 25–48. Task 1/2 imports and watches are well-formed.
- `productivity_classifier.dart:69` — confirmed: factory `ProductivityClassifier.withCalibration` starts here; the file currently has no `dart:io` import (verified by reading lines 1–11), so Task 5's "add `import 'dart:io' show Platform;`" is necessary and not a duplicate.
- `jni_productivity.cpp:70–114` — confirmed: function `nativeCreateProductivityWithIndividualData` exists with exactly those bounds, the silent `clCProductivity_Create(dev, &error)` fallback is at line 101, and the JNI parameter list matches what Task 4 enumerates for unused-parameter silencing.
- `jni_cardio.cpp:117` — confirmed: Cardio's calibrated factory uses the real `clCCardio_CreateCalibrated` symbol with `clCNFBCalibrator_ImportIndividualNFBData`, so Task 4 correctly scopes the JNI change to Productivity only.
- `CError.h:18` — confirmed: `clCError_ModuleIsNotSupported` exists; `clCError_ModuleAlreadyExists` (line 17) is the codename for the bug being fixed, which gives the chosen enum a nicely symmetric framing.
- `throw_sdk_error` is declared `extern` in `jni_productivity.cpp:25` — confirmed: defined in `jni_device_locator.cpp`. The `return 0;` after the throw matches the existing pattern at line 58.

All file paths, line numbers, and API references in the plan check out.

## Minor Observations (non-blocking)

### A. Task 6's doc-comment guidance is scoped to "each notifier" but point (d) is Productivity-specific

Task 6 says "In each notifier's class doc comment, replace the sentence … with a paragraph that states: (a) … (b) … (c) … (d) on Android, individual-NFB Productivity calibration is not available — the toggle still controls Cardio." Point (d) is genuinely relevant for `productivity_classifier_provider.dart` and arguably for `cardio_classifier_provider.dart` (since they share the toggle), but it has nothing to do with `mems_classifier_provider.dart`. The implementer should be able to scope this correctly, but the wording could be sharper. **Non-blocking — stylistic.**

### B. Task 6's heading mentions only `productivity_classifier_provider.dart`, but the body touches all three

The Task 6 heading reads: "Update doc comments and add a defensive Android fallback in `productivity_classifier_provider.dart`". The first paragraph then lists all three files. The defensive-fallback / `debugPrint` work is correctly scoped to Productivity only ("Additionally in `productivity_classifier_provider.dart` only"), but the doc-comment update is for all three. A reader skimming task titles might miss the cardio/mems doc-comment work. **Non-blocking — phrasing.**

### C. The fallback's user-visibility is silent by design

Per the resolved acceptance criterion, the Android user who toggles "Use NFB Calibration" gets calibrated Cardio + non-calibrated Productivity with no UI signal — only a single `debugPrint` line on first build. This is the intentional choice and the plan is explicit about it, but it is worth noting in the implementation PR description so that any future bug report "Productivity isn't using my calibration on Android" routes to the correct context. **Non-blocking — process note.**

### D. Roadmap entry is stale (carried over from v2)

The ROADMAP.md entry for task 56 still describes the previous dispose-before-create strategy. Not in scope to update during plan implementation, but worth a follow-up commit so the roadmap doesn't mislead a future reader. **Non-blocking — documentation hygiene.**

## Positive Notes

- The Context section is the strongest part of the plan: it correctly enumerates **both** SIGABRT triggers (toggle and calibration import) and traces each back to a specific `ref.watch` line. v2's incomplete-fix criticism is fully retired.
- The strategy is now symmetric across all three triggers: toggle locked by UI, calibration data snapshotted at build time, Android Productivity calibrated-path explicitly unsupported. Each piece has a single clear motivation.
- The acceptance criterion grew from one bullet to four well-scoped scenarios that cover toggle-pre-start, calibration-import-mid-stream, and the Android `UnsupportedError` contract.
- Task 4's prescription (`snprintf` + `clCError_ModuleIsNotSupported` + `[[maybe_unused]]`/`(void)param;` + single-line TODO) is now precise enough that the implementer cannot reasonably miscompile or under-implement it.
- Task 6's literal code block removes the last source of guess-the-scope ambiguity on the `try`/`catch`.
- The commit plan splits the change into one user-visible-fix commit and one Android-API-correctness commit — easier to revert independently if either lands a regression.
- All cross-file references (provider names, file paths, line numbers, the `nfb_classifier_provider.dart` precedent, the `CError.h` enum value) verify against the actual source.

## Final Verdict

The plan is implementation-ready. Issues v2 raised are individually addressed and each is now backed either by an explicit code snippet or a clearly worded constraint. The remaining observations are stylistic and do not affect correctness or completeness.

PLAN_REVIEW_PASS
