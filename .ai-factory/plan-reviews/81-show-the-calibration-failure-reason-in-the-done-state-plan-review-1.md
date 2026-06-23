## Code Review Summary

**Files Reviewed:** 2 plan-targeted files (`example/lib/providers/calibration_ui_state.dart`, `example/lib/screens/calibration_screen.dart`) + supporting model/barrel files
**Risk Level:** 🟢 Low

### Context Gates
- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — OK. Change is confined to the example app's presentation layer (`screens/` + `providers/` view-state). No boundary crossing: the mapper is pure UI text derived from an already-exported domain enum; no new dependency on `lib/src/`.
- **Rules (`.ai-factory/RULES.md`)** — Not present. Gate skipped (WARN, non-blocking).
- **Roadmap (`.ai-factory/ROADMAP.md`)** — OK. Plan maps 1:1 to the open milestone "Show the calibration failure reason in the Done state" (line 126) and the referenced spec `.ai-factory/notes/34-show-specific-calibration-failure-reason.md`. Wording of the mapper strings matches the roadmap entry verbatim.
- **Skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`)** — Not present. No project overrides to apply.

### Verified Assumptions (all correct)
- `NfbCalibrationFailReason` exists with exactly three values — `none`, `tooManyArtifacts`, `peakFrequencyAtBorder` (`lib/src/models/nfb_calibration_fail_reason.dart`). An exhaustive `switch` expression with no `default` is valid and idiomatic.
- The enum is exported from the barrel (`lib/neiry_kit.dart:24`), and both target files already import `package:neiry_kit/neiry_kit.dart`, so no new imports are required — as the plan states.
- `IndividualNfbData` exposes `failReason` (`individual_nfb_data.dart:30`) and `isValid` (`:57`). `CalibrationDone` holds `data` and surfaces `isValid` (`calibration_ui_state.dart:36-42`). `uiState.data.failReason` is reachable.
- Line references are accurate: the `Text('Status: ...')` widget sits at `calibration_screen.dart:212-217`, followed by `SizedBox(height: 12)` at line 218 — inserting the reason line between them is correct.
- The red-text styling pattern (`TextStyle(color: Colors.red)`) is already used in `_ErrorContent` (line 267), so it is consistent with the screen's existing convention.

### Critical Issues
None.

### Minor Notes (non-blocking)
- Task 2 renders the reason only when `!uiState.isValid`. By construction `failReason == none` ⇒ `isValid == true`, so `describeFailReason` never returns its empty-string branch at the call site. The `none → ""` mapping is still worth keeping for switch exhaustiveness and defensive correctness — no change needed, just noting the empty branch is effectively unreachable in this UI path.
- "Logging: minimal" in Settings — this change is pure presentation with no user action to log (no button/handler added), so adding no `nlog` call is consistent. No action required.

### Positive Notes
- Clean separation: the text mapper lives next to the view-state (`calibration_ui_state.dart`) rather than inside the widget, keeping `calibration_screen.dart` declarative.
- Reuses existing exported types and imports — zero new surface area, no barrel/edit churn in `lib/`.
- Strings, file paths, and enum names are all consistent across plan, roadmap, and spec note.

PLAN_REVIEW_PASS
