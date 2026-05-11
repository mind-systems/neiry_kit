# Code Review: 54-calibration-data-card

**Plan:** `.ai-factory/plans/54-calibration-data-card.md`
**Scope:** `example/lib/screens/calibration_screen.dart` (plus plan + plan-review docs)
**Risk Level:** 🟢 Low — UI-only change in the example app, no native or contract surface touched.

## Summary

The implementation lands the plan correctly:

- `import 'package:neiry_kit/neiry_kit.dart';` is added at `example/lib/screens/calibration_screen.dart:3` — the canonical public import used by all other example screens. `IndividualNfbData` is exported from `lib/neiry_kit.dart:19`, so the symbol resolves. ✓
- `_CalibrationDataCard()` is inserted after `_NfbCard()` with a `SizedBox(height: 12)` separator (lines 25–26), matching the existing spacing pattern. ✓
- The new widget (lines 296–324) is a `ConsumerWidget` with a `const` constructor — so it slots cleanly into the existing `const SingleChildScrollView`/`const Column` tree without dropping `const`. ✓
- `ref.watch(calibrationProvider).value ?? const IndividualNfbData()` (line 301) is type-safe: `CalibrationNotifier extends AsyncNotifier<IndividualNfbData?>` (calibration_provider.dart:15), so `.value` is `IndividualNfbData?`; the fallback uses default-constructed `IndividualNfbData()` with the documented defaults (`individualFrequency: 10.0`, `lowerFrequency: 7.0`, `upperFrequency: 13.0`, `individualBandwidth: 6.0`, `individualNormalizedPower: 0.5`). ✓
- Five `_BandRow` rows are rendered in the prescribed order with the prescribed labels; `individualPeakFrequencyPower` and `individualPeakFrequencySuppression` are correctly omitted. ✓
- `_BandRow` is reused without modification; values passed are non-null `double`, so the `—` branch is dead but harmless, as documented. ✓
- Section comment `// ── Calibration data card ──` mirrors the existing sectioning style. ✓

No bugs, security issues, or runtime concerns. The widget renders synchronously from already-watched provider state; no streams, no disposables, no platform calls.

## Findings

### Minor / UX (non-blocking)

1. **`_BandRow` label column is too narrow for the new labels.**
   `_BandRow` hardcodes `SizedBox(width: 60, child: Text(label))` (line 286). The existing labels in `_NfbCard` are short ("Delta", "Theta", "Alpha", "SMR", "Beta") and fit in 60 logical px. The new card's labels are longer: `Peak, Hz`, `Lower, Hz`, `Upper, Hz`, `Bandwidth, Hz` (~13 chars), `Norm. power` (~11 chars). With default Material text scale, `Bandwidth, Hz` and `Norm. power` will soft-wrap into two lines inside the 60 px box, producing a visually inconsistent row height in the new card. Not a crash, not a render-overflow assertion — just ugly.

   Mitigations (pick one, only if/when the UX matters):
   - Widen `_BandRow`'s `SizedBox` from `60` to `~110` (affects `_NfbCard` rows too — they'll have more leading whitespace but stay aligned).
   - Or parameterize the label width via an optional constructor arg, defaulting to 60.
   - Or inline a slightly wider `_BandRow` variant local to `_CalibrationDataCard`.

   Strictly speaking the plan said "reuse `_BandRow` without modification", and the implementer did that. This finding is a UX heads-up, not a defect against the plan.

2. **Pre-calibration placeholder is indistinguishable from a successful low-confidence calibration result.**
   The card shows the default `IndividualNfbData()` values (Peak 10.0, Lower 7.0, Upper 13.0, Bandwidth 6.0, Norm. power 0.5) both (a) before any calibration has ever run and (b) while a fresh `startFull`/`startQuick` is mid-flight (calibration_provider.dart sets `state = const AsyncValue.loading()` so `.value` is `null` and the fallback re-engages). A user could mistake the placeholder for real data. The plan explicitly accepts this trade-off ("always renders concrete values"), so this is intentional and out of scope here. Flagging for a future iteration — e.g., a subtle "no calibration data yet" caption when `calibrationProvider.value == null`.

3. **Long line at calibration_screen.dart:301.**
   `final data = ref.watch(calibrationProvider).value ?? const IndividualNfbData();` is ~85 chars. Within most Dart style configs (line length 80–100) this is borderline. Not a bug; `dart format` will leave it alone or wrap it consistently with the rest of the file. No action needed unless `flutter analyze` complains.

### No issues found

- No migrations or schema changes.
- No new dependencies; `neiry_kit` is already a path/transitive dep of the example app.
- No platform-channel surface touched.
- No race conditions — UI synchronously reads provider state.
- No security concerns (no I/O, no user input, no secrets).
- `const` correctness is preserved (`const _CalibrationDataCard();`, `const Text(...)`, `const SizedBox(...)`, `const EdgeInsets.all(16)`).
- Sentinel handling: not applicable — the C `-1` sentinel is normalized to `null` only for `timestamp` (individual_nfb_data.dart:62–66); the five fields shown here are always non-null `double` by construction.

## Recommendation

Ship it. The implementation matches the plan exactly. Findings 1–3 are non-blocking polish items the user can pick up later if desired.

REVIEW_PASS
