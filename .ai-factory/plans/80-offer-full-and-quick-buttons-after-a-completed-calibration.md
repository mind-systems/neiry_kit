# Plan: Offer Full and Quick buttons after a completed calibration

## Context
After a calibration completes (including artifact-invalid results), the Done card offers only a single `Recalibrate` button; this replaces it with both `Start Full Calibration` and `Start Quick Calibration` so either mode can be launched directly from the Done state.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Update Done card buttons

- [x] **Task 1: Replace Recalibrate with Full + Quick buttons in `_DoneContent`**
  Files: `example/lib/screens/calibration_screen.dart`
  In `_DoneContent` (≈ lines 196–244), keep "Calibration complete", the status line, and the `Export to File` `ElevatedButton`. Remove the single `Recalibrate` `OutlinedButton` (≈ lines 234–240) and replace it with two buttons mirroring `_IdleContent` (≈ lines 131–145):
    - `Start Full Calibration` → on tap call `nlog('Calibration: Start Full tapped', name: 'Neiry')` then `ref.read(calibrationProvider.notifier).startFull()`.
    - `Start Quick Calibration` → on tap call `nlog('Calibration: Start Quick tapped', name: 'Neiry')` then `ref.read(calibrationProvider.notifier).startQuick()`.
  Use the same button styling/spacing pattern already present in `_DoneContent`/`_IdleContent` (an `OutlinedButton` per re-run action with `SizedBox(height: 8)` between them). Both `startFull()` and `startQuick()` already exist on the notifier (`example/lib/providers/calibration_provider.dart`).

- [x] **Task 2: Verify analyzer is clean** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  Run `flutter analyze` (from `neiry_kit/` or `example/`) and confirm no new warnings/errors from the edited file.
