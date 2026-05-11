# Plan Review: 54-calibration-data-card

**Plan:** `.ai-factory/plans/54-calibration-data-card.md`
**Risk Level:** 🟢 Low

## Summary

The plan is small, focused, and structurally correct. It adds a third card to `CalibrationScreen` that mirrors `_NfbCard` and renders the five most user-facing fields of `IndividualNfbData`, with the default-constructed value used as the pre-calibration placeholder. I verified every claim against the codebase — type, exports, defaults, label list, import style — and they all hold up. The few notes below are wording polish, not blockers.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)**: present. This change is a leaf UI tweak in `example/lib/screens/`, not a contract change. No boundary impact. ✅
- **Rules (`.ai-factory/RULES.md`)**: not present. Skipped.
- **Roadmap (`.ai-factory/ROADMAP.md`)**: present. Task is a UI refinement of the example app — no explicit milestone linkage stated in the plan, but matches the running theme of completing the example app surfaces. Non-blocking. ⚠️ WARN: consider linking to the relevant ROADMAP item in future iterations.
- **Skill context (`.ai-factory/skill-context/aif-review/SKILL.md`)**: not present. No project-specific overrides to apply.

## Verified Facts

- `IndividualNfbData` is exported from `package:neiry_kit/neiry_kit.dart` via `export 'src/models/individual_nfb_data.dart';` (lib/neiry_kit.dart). ✓
- Defaults claimed in the plan match `lib/src/models/individual_nfb_data.dart` (lines 13–24): `individualFrequency: 10.0`, `lowerFrequency: 7.0`, `upperFrequency: 13.0`, `individualBandwidth: 6.0`, `individualNormalizedPower: 0.5`. ✓
- `calibrationProvider` is `AsyncNotifierProvider<CalibrationNotifier, IndividualNfbData?>` (calibration_provider.dart:147–149), so `ref.watch(calibrationProvider).value` is `IndividualNfbData?` — the `?? const IndividualNfbData()` fallback is type-safe. ✓
- `_BandRow` accepts `double?` and uses `value != null ? value!.toStringAsFixed(3) : '—'` (calibration_screen.dart:270–289). Passing non-null doubles is fine; the `—` branch is dead but harmless, exactly as the plan notes. ✓
- All other screens/providers in `example/lib/` use `import 'package:neiry_kit/neiry_kit.dart';` — that is the correct import style. ✓

## Findings

### Minor Issues

1. **Misleading "re-exports" wording (Task 1).**
   The plan says: *"Add the import only if `IndividualNfbData` is not already accessible through `calibration_provider.dart`'s re-exports."*
   `calibration_provider.dart` uses `import 'package:neiry_kit/neiry_kit.dart';` — it does **not** re-`export` anything. Dart import is not transitive. So the import is unconditionally required in `calibration_screen.dart`. The plan should simply state: *Add `import 'package:neiry_kit/neiry_kit.dart';` to `calibration_screen.dart`.*

2. **`const` constructor on `_CalibrationDataCard` is implicit, not specified.**
   `_NfbCard` declares `const _NfbCard();` (line 229), which is what allows it to sit inside the existing `const SingleChildScrollView(... const Column(...))` tree. The plan describes a fallback ("drop `const` from `Column` if needed") but doesn't tell the implementer to give the new widget a `const _CalibrationDataCard();` constructor. The cleanest, no-regression path is to mirror `_NfbCard` exactly — declare it `const`, keep the surrounding `const` tree intact. Suggest the plan explicitly require `const _CalibrationDataCard();` and drop the fallback paragraph.

### Suggestions (non-blocking)

3. **Label column width may clip "Bandwidth, Hz".**
   `_BandRow` hardcodes `SizedBox(width: 60, child: Text(label))` (line 283). Existing labels are short ("Delta", "Theta", etc.) so 60 px is fine; the new labels (`Peak, Hz`, `Lower, Hz`, `Upper, Hz`, `Bandwidth, Hz`, `Norm. power`) are ~10–13 chars. `Bandwidth, Hz` will likely overflow or wrap on smaller text scales. Either widen the label column (e.g., 100) in the new card or wrap the new rows in a slightly different layout. Out of scope for "mirror `_NfbCard`" but worth flagging; the implementer may want to bump the width to 100 in `_BandRow` itself or use a local helper in `_CalibrationDataCard`.

4. **During post-`startFull` `AsyncLoading`/`AsyncError` states the card silently renders default placeholder values.**
   The plan explicitly accepts this ("always renders concrete values"), so this is intentional. Just flagging that the same card will look identical between (a) pre-calibration idle and (b) a calibration run currently mid-flight that has wiped state via `state = const AsyncValue.loading()` (calibration_provider.dart:37, 81). If that's confusing UX, a future iteration could show a subtle "stale / no data yet" hint — not a plan defect.

### No Issues Found

- File paths are correct (`example/lib/screens/calibration_screen.dart`).
- No migrations involved (UI-only change).
- No security/perf concerns.
- No new dependencies.
- Logging policy: plan says "minimal" — appropriate for a passive readout widget.
- Testing policy: plan says "no" — acceptable for a thin UI mirror; the underlying provider and model are covered elsewhere.

## Recommendation

Plan is implementable as-is. Two small wording tightenings (items 1 and 2) would make it foolproof. Item 3 is worth a thought before implementation but not a planning bug.

PLAN_REVIEW_PASS
