## Plan Review Summary

**Plan Reviewed:** `27-productivitybridge.md`
**Files Affected:** `lib/src/api/classifiers/productivity_classifier.dart`, `ios/Classes/classifiers/ProductivityBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows "one bridge class per C API module" pattern, `DeviceStreamHandler` for EventChannels, correct folder placement. Sentinel-to-null conversion stays on Dart side (`orNull`), matching the documented boundary. No dependency rule violations.
- **RULES.md:** WARN — file does not exist.
- **ROADMAP.md:** PASS — plan implements the last unchecked iOS bridges milestone (`ProductivityBridge`). Event channel IDs, C API signatures, and error-param rules all match roadmap description.

### Critical Issues

None.

All issues from previous reviews have been resolved:

- **Review-1 suggestions** (float field count "11→10", explicit handle assignment, `createCalibrated` nil guard) — all incorporated into the current plan text.
- **Review-2 critical issue** (`individualNfbStream` Dart-side crash) — addressed as Task 1 (Phase 1), with the correct `Stream<void>` + `.map((_) {})` pattern matching `PhysioClassifier` lines 94–97.

Verified Task 1 changes against the codebase:
- `productivity_classifier.dart` line 148: current code decodes via `NfbUserState.fromMap` on an empty map → `TypeError`. Plan's fix bypasses decoding entirely. Correct.
- `productivity_classifier.dart` line 225: return type change `Stream<NfbUserState>` → `Stream<void>`. Correct.
- `nfb_user_state.dart` import (line 10): confirmed no other references to `NfbUserState` in the file after the fix. Safe to remove.

Verified Task 2–5 against `CProductivity.h`:
- 5 `SetOn*Event` functions: none take `clCError*`. `registerCallbacks()` correctly non-throwing.
- `clCProductivity_CreateWithIndividualData` takes `const clCIndividualNFBData*` directly (not calibrator handle). Factory path correctly differs from CardioBridge.
- `clCProductivity_ImportBaselines` takes `const clCProductivity_Baselines*` + `clCError*`. Matches plan.
- `clCProductivity_ResetAccumulatedFatigue` takes `clCError*`. Matches plan.
- `clCProductivity_StartBaselineCalibration` takes no `clCError*`. Matches plan.
- No `clCProductivity_SetOnErrorEvent` exists in the header. 6 stream handlers (excluding error) is correct for the 5 C callbacks + the dual-emit from `SetOnBaselineUpdateEvent`.

Verified plugin wiring (Task 5) against `NeiryKitPlugin.swift`:
- `"neiry_kit/productivity"` MethodChannel registered at line 46 but no dispatch case exists (falls through to `FlutterMethodNotImplemented`). Plan correctly adds `handleProductivityCall`.
- Dispose chain at line 143–150 has no `productivityBridge?.dispose()`. Plan correctly adds it.
- EventChannel handler resolution chain (lines 607–623) has no productivity handlers. Plan correctly adds `productivityHandlers` dict.
- All 7 productivity EventChannel IDs are already in the registration list (lines 586–603). The bridge covers 6 of them; `productivityError` stays on `StubStreamHandler` because the C API has no error callback — this is harmless (the Dart stream simply never emits).

### Suggestions

None.

### Positive Notes

- The Dart-side crash fix (Task 1) was cleanly integrated as a new Phase 1, keeping the scope focused without overloading the bridge tasks.
- The dual-emit from `SetOnBaselineUpdateEvent` (parsed map → `baselinesHandler`, raw struct bytes → `calibratedHandler`) is a clean workaround for the absence of a dedicated `SetOnCalibratedEvent` in the Productivity C API. Both Dart streams get their expected types from a single callback.
- The `createCalibrated` nil guard for `calibrationData` is explicitly required — correctly distinguishing Productivity (data struct required) from Cardio (calibrator handle, nil-tolerant).
- All error-param decisions match the C header exactly: non-throwing `registerCallbacks()` (Emotions pattern), throwing `create`/`createCalibrated`/`importBaselines`/`resetAccumulatedFatigue` (with `clCError*`), fire-and-forget `startBaselineCalibration` (no error param).
- The commit plan separates the Dart fix from the native bridge — a clean boundary that makes each commit independently reviewable.

PLAN_REVIEW_PASS
