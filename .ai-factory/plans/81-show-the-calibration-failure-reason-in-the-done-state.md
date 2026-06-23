# Plan: Show the calibration failure reason in the Done state

## Context
When a calibration completes but is invalid (`IndividualNfbData.failReason != none`), the Done card shows only "Status: invalid". This milestone surfaces the concrete reason as readable red text so the user understands why it failed.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Implement failure-reason text

- [x] **Task 1: Add `describeFailReason` mapper**
  Files: `example/lib/providers/calibration_ui_state.dart`
  Add a top-level function `String describeFailReason(NfbCalibrationFailReason reason)` that maps each enum value to user-facing text:
  - `tooManyArtifacts` → `"Too many EEG artifacts — sit still and reduce movement"`
  - `peakFrequencyAtBorder` → `"Alpha peak at the band border — result may be unreliable"`
  - `none` → `""` (empty string)
  Use a `switch` expression over `NfbCalibrationFailReason` (exhaustive, no default). `NfbCalibrationFailReason` is already exported via the existing `package:neiry_kit/neiry_kit.dart` import at the top of the file.

- [x] **Task 2: Render the reason line in `_DoneContent`** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  In `_DoneContent.build`, after the existing `Text('Status: ...')` widget (around line 217), add a conditional widget: when `!uiState.isValid`, render `describeFailReason(uiState.data.failReason)` as a red `Text` line under the status (e.g. `style: const TextStyle(color: Colors.red)`, preceded by a small `SizedBox(height: 4)`). When the calibration is valid, render nothing for this line. `uiState.data` (`IndividualNfbData`) exposes `failReason`; `CalibrationDone` already holds `data`. The `describeFailReason` function comes from the existing `../providers/calibration_ui_state.dart` import.
