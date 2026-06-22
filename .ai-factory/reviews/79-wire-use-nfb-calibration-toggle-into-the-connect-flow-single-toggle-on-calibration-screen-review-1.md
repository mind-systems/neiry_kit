# Code Review: Wire Use-NFB-Calibration toggle into the connect flow

**Plan:** `79-wire-use-nfb-calibration-toggle-into-the-connect-flow-single-toggle-on-calibration-screen.md`
**Scope:** 6 Dart files in `example/lib` (no native changes)
**Risk Level:** 🟢 Low

## Summary

The implementation matches the plan task-for-task. The redundant `useMemsCalibrationToggleProvider` is removed, the single `useCalibrationToggleProvider` now governs MEMS + Productivity + Cardio, the toggle UI is hosted on the calibration screen, `NeiryService.connect` gained the `useCalibration` gate, and `device_screen._connect()` reads the providers one-shot and passes them through. `flutter analyze` on all six changed files reports **No issues found**.

## Verification Performed

- **Full `git diff HEAD` + `git status`** reviewed; each changed file read in surrounding context.
- **`flutter analyze`** on all six changed files → clean (0 issues).
- **Dangling-reference sweep:**
  - `useMemsCalibrationToggleProvider` — zero references remain anywhere in `example/lib`.
  - `useCalibrationToggleProvider` — defined once, read in `device_screen.dart`, watched/set in `calibration_screen.dart`. Correct.
  - `nfbCalibrationProvider` — still written by `calibration_provider.dart` and read at connect / on the new card. The note-30 invariant ("do NOT clear `nfbCalibrationProvider` on disconnect", `calibration_provider.dart:49`) is preserved.
- **Unused-import check:**
  - `mems_screen.dart` — both `nfb_calibration_provider.dart` and `utils/nlog.dart` removed; confirmed `nlog` has no remaining usage in that file, and `device_state_providers.dart` is correctly kept (used by the `isConnected` check).
  - `productivity_cardio_screen.dart` — `nfb_calibration_provider.dart` removed; `nlog` import correctly **kept** (still used at lines 185, 200 for the baseline/reset actions).

## Correctness Analysis

- **Gate logic (`neiry_service.dart`):** `final cal = useCalibration ? _nfbData : null;` then `_productivity`/`_cardio`/`_mems` branch on `cal != null`, while `_nfb` keeps `calibration: _nfbData` unconditionally. This is exactly the intended behavior: NFB always uses calibration when present; the flag gates only the other three. `_nfbData = nfbData` is still assigned before construction, so the connect-error reset path is intact.
- **Null-safety edge cases:** When `useCalibration == true` but `_nfbData == null`, `cal` is `null` → all classifiers built generic, no crash, NFB also gets null calibration. When `useCalibration == false`, `cal` is `null` regardless of `nfbData`. Both safe.
- **Toggle UI (`calibration_screen.dart`):** `value: useCal && nfbData != null` with `onChanged: null` while `nfbData == null` correctly disables the switch until a calibration exists. Subtitle wording matches the plan. The card has a `const` constructor and sits in the `const` children list — valid.
- **Connect wiring (`device_screen.dart`):** Uses `ref.read` (one-shot at connect), not `watch` — correct for a construction-time parameter that applies on reconnect by design. No race: the reads happen synchronously inside `_connect()` before the awaited `connect` call.
- **No runtime concerns:** Pure Dart wiring over pre-existing `*.withCalibration` factory constructors; no migrations, no platform-channel/contract changes, no type mismatches, no threading changes.

## Non-Blocking Observations

1. **Unnecessary `const` removal in `calibration_screen.dart` (cosmetic).** `body:` was changed from `const SingleChildScrollView(...)` to a non-const `SingleChildScrollView` with `padding: const EdgeInsets.all(16)` and `children: const [...]`. Because every child (including the new `_UseCalibrationCard()`) has a `const` constructor, the entire `SingleChildScrollView` could have remained `const`. The current form is fully correct and analyzer-clean — just a marginally missed const-canonicalization. No action required.

2. **Toggle label vs. NFB (by design, pre-existing).** The switch is titled "Use NFB Calibration" yet does not gate the NFB classifier itself. The subtitle "Applies to Productivity, Cardio & MEMS" mitigates this, and it matches the agreed design. No action.

No correctness, security, or data-integrity issues found.

REVIEW_PASS
