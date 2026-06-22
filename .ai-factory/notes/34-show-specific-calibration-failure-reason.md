# Show the calibration failure reason in the Done state

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- A calibration can complete but be invalid — `IndividualNfbData.failReason != none` (`isValid == false`). The most common case is too many EEG artifacts.
- The Done card (`_DoneContent` in `example/lib/screens/calibration_screen.dart`) currently shows only "Status: invalid" in red. The user wants to see **why** it failed.
- Surface the concrete `NfbCalibrationFailReason` as readable text next to the status.

## Details

### Current state

`_DoneContent` (`example/lib/screens/calibration_screen.dart`) shows `Text('Status: ${uiState.isValid ? 'valid' : 'invalid'}')`. `CalibrationDone` carries `data` (`IndividualNfbData`) and `isValid`; the reason lives in `data.failReason` (`example/lib/providers/calibration_ui_state.dart`, `lib/src/models/individual_nfb_data.dart`).

`NfbCalibrationFailReason` (`lib/src/models/nfb_calibration_fail_reason.dart`): `none`, `tooManyArtifacts`, `peakFrequencyAtBorder`.

### Exact change

1. Add a mapper `String describeFailReason(NfbCalibrationFailReason reason)`:
   - `tooManyArtifacts` → "Too many EEG artifacts — sit still and reduce movement"
   - `peakFrequencyAtBorder` → "Alpha peak at the band border — result may be unreliable"
   - `none` → "" (empty)
2. In `_DoneContent`, when `!uiState.isValid`, render `describeFailReason(uiState.data.failReason)` as a line under the "Status: invalid" text (red).

### Verify

Produce an artifact-invalid calibration → the Done card shows "Status: invalid" followed by "Too many EEG artifacts …". A valid result shows no reason line. `flutter analyze` clean.
