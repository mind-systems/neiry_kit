# Plan Review: Wire Use-NFB-Calibration toggle into the connect flow

**Plan:** `79-wire-use-nfb-calibration-toggle-into-the-connect-flow-single-toggle-on-calibration-screen.md`
**Files Reviewed:** 6 target files + 2 supporting (calibration_provider.dart, ARCHITECTURE.md, ROADMAP.md)
**Risk Level:** 🟢 Low

## Verdict

The plan is accurate, internally consistent, and matches the codebase. Every referenced line number, symbol, and API surface was verified against the actual source. The premise holds: `device_screen._connect()` currently calls `connect(serial)` with no `nfbData` and never reads the toggle providers, so the "Use NFB Calibration" toggle is genuinely dead today. The `*.withCalibration` constructors and the `NeiryService.connect(nfbData:)` parameter already exist, so this is pure UI/connect-flow wiring with no native changes — as the plan states.

## Context Gates

- **Architecture (ARCHITECTURE.md):** PASS. All changes live in `example/` and use only the public `neiry_kit` barrel API + Riverpod providers. No `lib/src/` imports, no cross-layer violations. Consistent with the rule "`example/` depends on `lib/` public API only."
- **Rules (.ai-factory/RULES.md):** Not present — no rule gate to apply (WARN: optional file absent, non-blocking).
- **Roadmap (ROADMAP.md):** PASS. The work maps exactly to the open milestone at ROADMAP.md line 120 ("Wire Use-NFB-Calibration toggle into the connect flow (single toggle on calibration screen)"). The milestone references spec note `.ai-factory/notes/32-wire-use-nfb-calibration-toggle-into-connect.md`; the plan's approach (collapse to one `useCalibrationToggleProvider`, host on calibration screen, add `useCalibration` gate, `ref.read` at connect) aligns with the milestone description. The plan also correctly honors the dependency on milestone note 30 (do NOT clear `nfbCalibrationProvider` on disconnect — verified in `calibration_provider.dart:48-54`).

## Critical Issues

None.

## Verification Notes (confirmed correct)

- **Task 1** — `connect` signature at `neiry_service.dart:111-115` matches; `_nfbData = nfbData` at line 123; classifier block at 142-153; `_safeProductivityWithCalibration` exists at 506-515 and `CardioClassifier.withCalibration` / `MEMSClassifier.withCalibration` are the correct factory names. Gating `_productivity`/`_cardio`/`_mems` on a local `cal` with Dart null-promotion is valid.
- **Task 2** — Grep confirms `useMemsCalibrationToggleProvider` is referenced ONLY in `mems_screen.dart` (lines 18, 45) and its definition (line 16). Deleting it + Task 6 removes all references. No orphan references elsewhere.
- **Task 3** — `calibration_screen.dart` does not currently import `nfb_calibration_provider.dart`; the root `Column`/`SingleChildScrollView` is `const` (lines 20-30) — the plan's note to drop `const` when inserting a non-const `ConsumerWidget` is correct. `nfbCalibrationProvider` is the right gate source: it is what gets passed to `connect`, and it is written by `_writeToSharedProvider()` / `importFromFile()` and deliberately preserved across disconnect.
- **Task 4** — `device_screen.dart` is a `ConsumerStatefulWidget` (so `ref` is available in `_connect()`); line 110 is the exact call to replace; `ref.read` (one-shot) is the correct choice over `watch`.
- **Task 5 / Task 6** — Line ranges for the `SwitchListTile`s, the `nfbData`/`useCalibration` reads, the imports to remove, and the `device_state_providers.dart` import to keep (used for the `isConnected` check) are all accurate.

## Non-Blocking Observations

1. **Task 1 wording — `cal` source.** The plan writes `final cal = useCalibration ? nfbData : null;` and says `_nfb` "keeps `calibration: nfbData`". The existing code uses the field `_nfbData` (not the parameter `nfbData`) throughout the classifier block. Since `_nfbData = nfbData` is assigned at line 123, both are equivalent, but for consistency with the surrounding code the implementer should prefer `final cal = useCalibration ? _nfbData : null;` and leave `_nfb`'s `calibration: _nfbData` literally unchanged. No behavioral difference.

2. **Toggle label vs. NFB classifier (UX).** The single switch is labeled "Use NFB Calibration" but, by design, does NOT gate the NFB classifier itself (NFB always receives calibration if present). The plan's subtitle "Applies to Productivity, Cardio & MEMS" mitigates this, and the behavior matches the pre-existing design. Acceptable; flagged only so the implementer keeps the subtitle wording exactly.

3. **Post-disconnect display inconsistency (pre-existing).** After disconnect, `calibrationProvider` resets to `null` (data card shows default placeholder values via `?? const IndividualNfbData()`), while `nfbCalibrationProvider` persists — so the new toggle stays enabled/ON. This is consistent with milestone note 30's intent ("toggles stay enabled" after disconnect) and is not introduced by this plan. Similarly, on a cold open where the SDK has cached calibration, the data card may show real values while the toggle reads "Run calibration first to enable" (because `nfbCalibrationProvider` is only written on a completed run/import, not on cold-open `getCalibrationData()`). Both are pre-existing edge cases, not regressions. No action required.

4. **Commit strategy is sound.** The single-commit rationale is correct: deleting `useMemsCalibrationToggleProvider` (Task 2) breaks `mems_screen.dart` until Task 6, so the set must land together to keep the build green.

## Positive Notes

- Line-level precision throughout — the plan reads like it was written against the actual files, which it clearly was.
- Correctly identifies and preserves the subtle cross-milestone invariant (note 30: never clear `nfbCalibrationProvider`).
- Correct dependency ordering between tasks, and correct choice of `ref.read` vs `ref.watch` at connect time.
- Scope is tight and matches the roadmap milestone exactly; no scope creep, no unnecessary native changes.

PLAN_REVIEW_PASS
