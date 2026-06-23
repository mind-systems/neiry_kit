# Code Review: Show the calibration failure reason in the Done state

**Scope:** `example/lib/providers/calibration_ui_state.dart`, `example/lib/screens/calibration_screen.dart`
**Risk:** 🟢 Low

## Summary
The change adds a `describeFailReason` mapper and renders its output as a red line under "Status: invalid" in `_DoneContent`. The implementation matches the plan and spec exactly. `flutter analyze` is clean on both files.

## Correctness verification

- **Exhaustive switch.** `describeFailReason` switches over all three `NfbCalibrationFailReason` values (`tooManyArtifacts`, `peakFrequencyAtBorder`, `none`) with no `default`. The enum has exactly those three members (`lib/src/models/nfb_calibration_fail_reason.dart`), so the switch expression is exhaustive and compiles without warning.

- **String fidelity.** The two messages match the roadmap/spec verbatim, including the em-dashes.

- **Guarded rendering is sound.** `isValid` is defined as `failReason == NfbCalibrationFailReason.none` (`individual_nfb_data.dart:57`). Therefore inside the `if (!uiState.isValid)` block, `failReason` is guaranteed to be non-`none`, so `describeFailReason` always returns a non-empty string at this call site. The empty-string branch for `none` is effectively unreachable here but correctly kept for switch exhaustiveness. No risk of rendering an empty red line.

- **Imports.** Both files already import `package:neiry_kit/neiry_kit.dart`, which exports `NfbCalibrationFailReason` and `IndividualNfbData`. `describeFailReason` is a top-level function in `calibration_ui_state.dart`, already imported by the screen. No new imports needed; analyzer confirms no unresolved references.

- **Widget construction.** The `if (...) ...[ SizedBox, Text ]` collection-spread is the existing idiom used elsewhere in this file (e.g. the `uiState == null` branch in `_CalibrationCard`). `const SizedBox` and `const TextStyle` are correctly const. The red styling matches the existing `_ErrorContent` convention.

## Runtime considerations
No state, async, platform-channel, or migration surface is touched — this is pure presentation derived from already-materialized data. No race conditions or null-safety gaps. `data.failReason` is non-nullable with a `none` default, so no null access is possible.

## Findings
None.

REVIEW_PASS
