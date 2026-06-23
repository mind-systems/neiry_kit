# Code Review: Offer Full and Quick buttons after a completed calibration

## Scope
- `example/lib/screens/calibration_screen.dart` (only code change)

## Summary
The change replaces the single `Recalibrate` `OutlinedButton` in `_DoneContent` with two `OutlinedButton`s — `Start Full Calibration` → `startFull()` and `Start Quick Calibration` → `startQuick()` — matching the plan and spec.

## Verification
- Both `startFull()` (line 61) and `startQuick()` (line 112) exist on the notifier in `example/lib/providers/calibration_provider.dart`. ✓
- `nlog` labels mirror `_IdleContent` exactly (`'Calibration: Start Full tapped'`, `'Calibration: Start Quick tapped'`). ✓
- Spacing pattern follows the existing convention (`SizedBox(height: 8)` between buttons, `OutlinedButton` per re-run action). ✓
- "Calibration complete", the status line, and `Export to File` are preserved. ✓
- No imports, types, or other call sites affected; change is purely additive UI within one widget.

## Findings
None. The change is minimal, correct, and consistent with the surrounding code. No correctness, runtime, or security concerns.

REVIEW_PASS
