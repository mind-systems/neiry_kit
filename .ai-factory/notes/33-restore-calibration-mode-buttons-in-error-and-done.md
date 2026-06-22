# Offer Full and Quick buttons after a completed calibration

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- After a calibration completes — including an artifact-invalid result (`failReason != none`) — the screen shows the Done state (`_DoneContent` in `example/lib/screens/calibration_screen.dart`), whose only re-run control is a single `Recalibrate` button wired to `startFull()`. Quick calibration is reachable only from the Idle state.
- The user wants, from a completed/failed calibration, to launch **either** a full **or** a quick calibration directly. Replace the single `Recalibrate` with both Start Full and Start Quick buttons.

## Details

### Current state

`_DoneContent` (`example/lib/screens/calibration_screen.dart`, ≈ lines 196–244) renders, for a `CalibrationDone` state:
- "Calibration complete" + a "Status: valid/invalid" line (`uiState.isValid`).
- `Export to File` (`ElevatedButton` → `exportToFile()`).
- `Recalibrate` (`OutlinedButton` → `ref.read(calibrationProvider.notifier).startFull()`).

The notifier already exposes `startFull()` and `startQuick()` (`example/lib/providers/calibration_provider.dart`); Idle (`_IdleContent`) uses both.

### Exact change

In `_DoneContent`, keep "Calibration complete", the status line, and `Export to File`. Replace the single `Recalibrate` button with two buttons:
- `Start Full Calibration` → `ref.read(calibrationProvider.notifier).startFull()`
- `Start Quick Calibration` → `ref.read(calibrationProvider.notifier).startQuick()`

Keep the existing `nlog(...)` lines for taps (mirror the labels used in `_IdleContent`).

### Verify

Complete a calibration (or produce an artifact-invalid one) → the Done card shows Export + Start Full + Start Quick. Tapping Start Quick runs a quick calibration; tapping Start Full runs a full one. `flutter analyze` clean.
