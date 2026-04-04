## Plan Review: 09-nfbclassifier (Round 2)

**Files Reviewed:** 8 (plan + channel_names.dart, device.dart, device_locator.dart, neiry_kit.dart, nfb_user_state.dart, individual_nfb_data.dart, 04-dart-api-classifiers.md)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** OK — plan enforces the `device.isStarted` guard in the factory constructor, satisfying the anti-pattern rule "Starting classifiers before `clCDevice_Start` — enforce this in the Dart API". File placement (`lib/src/api/classifiers/nfb_classifier.dart`) matches the documented folder structure. Dependency flow (`api/ → channel/ + models/`) is respected.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** plan aligns with the `NfbClassifier` milestone under "Dart API". No linkage issues.

### Verification of Round 1 Fixes

Both critical issues from plan-review-1 have been addressed:

1. **Error handling on native creation (was CRITICAL):** Plan now specifies `_nativeReady` with `.catchError()` storing into `_createError`, a `_checkReady()` guard before stream access, and `dispose()` that checks `_createError` before calling native destroy. This matches DeviceLocator's proven pattern (device_locator.dart lines 38-47, 89-93, 224-230).

2. **`device.isStarted` guard (was CRITICAL):** Factory constructor now guards with `if (!device.isStarted) throw StateError(...)` before delegating to the private constructor.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- Error handling lifecycle is now complete and consistent with DeviceLocator — `.catchError()` prevents unhandled Future errors, `_checkReady()` guards stream access, and `dispose()` gracefully skips native destroy when creation failed.
- The `isStarted` guard enforces the SDK ordering constraint synchronously at construction time, giving callers a clear error instead of an async platform exception.
- All channel names (`NeiryChannels.nfb`, `NeiryEvents.nfbState`, `NeiryEvents.nfbError`), argument keys (`NeiryArgs.serial`, `NeiryArgs.calibrationData`), and method names (`ClassifierMethods.create`, `createCalibrated`, `dispose`) verified against channel_names.dart — all correct.
- Import paths from the new `classifiers/` subdirectory are valid: `../device.dart`, `../../channel/channel_names.dart`, `../../models/nfb_user_state.dart`, `../../models/individual_nfb_data.dart`.
- `IndividualNfbData.toMap()` returns `Map<String, dynamic>` (individual_nfb_data.dart line 90) — the plan's `calibration.toMap()` call is correct.
- Task 1 (adding `ClassifierMethods.dispose`) is properly scoped as a shared contract change, benefiting all future classifier implementations.
- Stream FIFO ordering assumption (no `await _nativeReady` before opening EventChannels) is consistent with DeviceLocator's documented approach and the Flutter platform channel dispatch model.

PLAN_REVIEW_PASS
