# Plan Review: Migrate calibration_screen and CalibrationProvider

**Plan file:** `.ai-factory/plans/71-migrate-calibration-screen-and-calibrationprovider.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md** — not directly applicable; this is a final mop-up step of a multi-milestone refactor.
- **RULES.md** — no rules file present; no `aif-review` skill-context override directory at `.ai-factory/skill-context/`.
- **ROADMAP.md** — milestone "Migrate calibration_screen and CalibrationProvider" is the unchecked last item under "Example app architecture refactor". Plan scope matches milestone description. ✅

## Codebase verification

Cross-checked plan claims against actual code:

1. **`example/lib/screens/calibration_screen.dart`**
   - Line 10 import `'../providers/nfb_classifier_provider.dart';` — confirmed.
   - `_NfbCard.build()` at lines 272–311 — confirmed.
   - `final classifier = ref.watch(nfbClassifierProvider);` at line 277 — confirmed.
   - Existing `if (classifier == null) ... else ref.watch(nfbStateProvider).when(...)` block — confirmed at lines 290–306.

2. **`example/lib/providers/classifier_stream_providers.dart`**
   - `nfbStateProvider` is at line 37, of type `StreamProvider<NfbUserState>` — confirmed.

3. **`example/lib/providers/`** — confirmed `nfb_classifier_provider.dart` is already gone (per ROADMAP milestone 66). Listing confirms the deleted providers from Task 3 are all already absent on disk.

4. **`grep` for `nfbClassifierProvider | nfb_classifier_provider`** across `example/` returns only the two lines in `calibration_screen.dart`. No other consumer remains. Task 3's "if any file still imports..." defensive clause therefore has nothing to clean up beyond Task 1 already.

5. **`grep` for the other deleted provider names** (`emotions_classifier_provider`, `physio_classifier_provider`, `cardio_classifier_provider`, `mems_classifier_provider`, `productivity_classifier_provider`, `device_locator_provider`, `active_device_provider`) returns **zero matches** in `example/lib/`. Prior milestones (65, 66, 68, 69) cleaned them up.

6. **`NfbUserState`** in `lib/src/models/nfb_user_state.dart` has fields `delta/theta/alpha/smr/beta` typed `double?`. `_BandRow` accepts `double?` and prints `—` for null. All consistent with the plan.

7. **`CalibrationNotifier`** in `calibration_provider.dart` uses `NfbCalibrator` (static class) and writes to `nfbCalibrationProvider` — does not touch any deleted device/classifier providers. Plan correctly says no changes needed here.

## Critical Issues

None.

## Minor Notes

1. **Loading-text wording change.** The original code shows `'Waiting for device...'` only when the classifier handle was null, and `'Waiting for NFB data...'` while waiting for the first sample on a connected device. The plan collapses both into a single `'Waiting for device...'` (loading branch). The plan's Task 2 rationale acknowledges this explicitly and the new architecture genuinely does not let the screen distinguish "no device" from "device connected, stream silent". This is a small UX regression (the message will read "Waiting for device..." even when a device is connected and streaming), but it is the correct trade-off given the new stream-based provider has no separate "no device" signal. No action required, but worth flagging that the message could equally well be `'Waiting for NFB data...'` to avoid implying disconnection while connected. Implementer's call.

2. **Task 3 is essentially empty in practice.** Grep confirms `calibration_screen.dart` is the only remaining consumer of any deleted provider in the example app. After Tasks 1+2, `flutter analyze` should be clean directly. Task 3 is therefore a defensive verification step rather than expected cleanup work — this matches the plan's "Expected outcome after Task 2: clean" wording. Fine as-is.

3. **`AsyncValue.when` over `valueOrNull` check.** The milestone description in ROADMAP suggested `ref.watch(nfbStateProvider).valueOrNull != null` style. The plan instead uses the full `.when(loading/error/data)` pattern. This is strictly better — it preserves the existing error branch (`'Error: $e'`) the code already had under the original `nfbStateProvider.when(...)`. Good call to keep the error path.

## Positive Notes

- Plan correctly scopes work to one widget (`_NfbCard`) in one file and explicitly lists what NOT to touch (`_BandRow`, `_CalibrationCard`, `_CalibrationDataCard`, `_IdleContent`, `_ActiveContent`, `_DoneContent`, `_ErrorContent`). Reduces blast radius.
- File path and line-number references are accurate to the current code on disk.
- Dependency ordering between tasks (1 → 2 → 3) is correct.
- Preserves the existing `Card`/`Padding(16)`/`Column` shell and the `_BandRow` data layout, keeping the visual contract intact.
- No security or migration concerns — UI-only change in the example app.

PLAN_REVIEW_PASS
