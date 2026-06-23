# Plan Review: Offer Full and Quick buttons after a completed calibration

**Plan:** `.ai-factory/plans/80-offer-full-and-quick-buttons-after-a-completed-calibration.md`
**Risk Level:** 🟢 Low

## Scope

A single-file UI tweak in the example app: replace the lone `Recalibrate`
button in the calibration Done card with `Start Full Calibration` +
`Start Quick Calibration`. No native code, no contracts, no migrations.

## Verification against the codebase

Every concrete claim in the plan checks out:

- **`_DoneContent` location & content** — present at `calibration_screen.dart:196–244`. Has the "Calibration complete" text, the status line (`uiState.isValid ? 'Status: valid' : 'Status: invalid'`), the `Export to File` `ElevatedButton`, and the `Recalibrate` `OutlinedButton`. ✅
- **`Recalibrate` button to remove** — at lines `233–240` (an `OutlinedButton` calling `startFull()`). The plan's "≈ lines 234–240" is accurate enough. ✅
- **`_IdleContent` reference pattern** — at lines `120–157`; the Start Full / Start Quick buttons it cites are at `131–145`. ✅
- **Notifier methods exist** — `startFull()` (`calibration_provider.dart:61`) and `startQuick()` (`:112`) both exist and are public. ✅
- **`nlog` import** — already imported (`calibration_screen.dart:11`), and the exact log strings `'Calibration: Start Full tapped'` / `'Calibration: Start Quick tapped'` already exist verbatim in `_IdleContent`, so reuse is consistent. ✅
- **Logging level** — "minimal" matches the existing one-line `nlog` per tap convention. ✅

## Context Gates

- **Architecture** (`.ai-factory/ARCHITECTURE.md` present): WARN — none. This is an example-app screen change, outside the plugin's public API / bridge layers; no boundary or dependency concerns.
- **Rules** (`.ai-factory/RULES.md`): WARN — file absent; no project rule set to enforce.
- **Roadmap** (`.ai-factory/ROADMAP.md` present): WARN — no roadmap line corresponds to this example-app UI refinement. Acceptable: the roadmap tracks plugin/bridge milestones, not example-screen polish. No linkage required, but worth noting the work is not roadmap-tracked.

## Observations (non-blocking)

1. **Button-widget ambiguity.** Task 1 says to mirror `_IdleContent` (which uses `ElevatedButton` for Start Full / Start Quick) but then explicitly prescribes "an `OutlinedButton` per re-run action." These two instructions point at different widgets. It is not a correctness issue — either renders and works — but the implementer must pick one. Recommendation: keep `OutlinedButton`, since the Done card's existing re-run affordance (`Recalibrate`) is already an `OutlinedButton` and the primary action on the Done card (`Export to File`) is the `ElevatedButton`; using `OutlinedButton` for both re-run actions preserves that visual hierarchy. Worth making the plan unambiguous on this single point.

2. **Behavior parity is preserved.** The removed `Recalibrate` button called `startFull()`; the new `Start Full Calibration` button calls the same method, so no regression in the "re-run a full calibration" path. The added `startQuick()` path is already exercised from `_IdleContent`, so no new notifier behavior is introduced.

3. **No state-machine concerns.** From the Done state, `calibAsync` holds a non-null value; `startFull()`/`startQuick()` both set `state = AsyncValue.loading()` first, which drives the card back through `_ActiveContent` / generic-loading correctly. No special handling needed beyond what already exists.

## Positive Notes

- Plan is precise, cites exact symbols and line ranges, and correctly identifies that both notifier methods already exist (no provider changes needed).
- Includes an explicit `flutter analyze` verification task — appropriate for a Dart/Flutter edit.
- Correctly scopes the change to the example app only and leaves the plugin API untouched.

## Verdict

The plan is solid and implementable as written. The only refinement worth making is resolving the `ElevatedButton` vs `OutlinedButton` wording so the implementer has no choice to make — but this does not block implementation.

PLAN_REVIEW_PASS
