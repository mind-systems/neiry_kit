# Plan Review: Fix classifier singleton lifecycle — create at connect, not at start

**Files Reviewed:** 14 (6 classifiers + 6 providers + 2 screens + cross-referenced device.dart, active_device_provider.dart, device_state_providers.dart, device_screen.dart)
**Risk Level:** 🟢 Low

## Verification of Plan Assumptions

### File paths — all correct
- `lib/src/api/classifiers/{cardio,mems,productivity,emotions,nfb,physio}_classifier.dart` — all exist with the expected factory-guard shape.
- `example/lib/providers/{cardio,mems,productivity,emotions,nfb,physio}_classifier_provider.dart` — all exist and all six watch `deviceIsStartedProvider` exactly as the plan describes.
- `example/lib/screens/{mems_screen.dart,productivity_cardio_screen.dart}` — both exist and both contain the literal `final canEditToggle = uiState != DeviceUiState.started;` line.

### API references — all valid
- `Device.isConnected` is exposed at `lib/src/api/device.dart:299`. Replacement target is real.
- `Device.isStarted` at `lib/src/api/device.dart:302`. Source field exists.
- `DeviceUiState.idle` enum value exists in `example/lib/providers/device_state_providers.dart:27`.

### Factory shape per file — matches plan
- Cardio: two factories (`CardioClassifier`, `CardioClassifier.withCalibration`) — plan's "both factories" wording matches.
- MEMS: two factories — matches.
- Productivity: two factories — matches.
- Emotions / NFB / Physio: one factory each — plan's "every factory" wording is still correct, just degenerate.

### Import-removal safety — verified
Every classifier provider imports `device_state_providers.dart` solely for `deviceIsStartedProvider`. None of them use `DeviceUiState`, `deviceUiStateProvider`, or `deviceConnectionStateProvider`. Removing the import after dropping the `isStarted` read is safe and leaves no dangling symbol.

### Dependency ordering — sound
Phase 1 (loosen factory guard) → Phase 2 (provider stops gating on `isStarted`) → Phase 3 (UI toggle re-gated on idle). If Phase 2 ran before Phase 1, the provider would call the factory at connect-time and hit `StateError('… before Device.start()')`. The plan's per-task `(depends on Task N)` annotations preserve the safe order.

### Toggle re-gating logic — correct
Before: toggle editable in `idle` and `connected` (disabled only in `started`). After plan: toggle editable only in `idle`. Rationale: with the classifier alive from connect, flipping `useCalibrationToggleProvider` while connected would invalidate the `ref.watch` and rebuild the classifier — which is exactly the re-creation that the plan's Context says crashes on Android. The tightened gate prevents this regression. ✓

## Findings

### Critical Issues
None.

### Architectural notes / non-blocking gaps

1. **Class-level lifecycle docs in classifier files are not updated.** Each classifier (e.g. `cardio_classifier.dart:42-45`, `mems_classifier.dart:33-38`, `productivity_classifier.dart:43-48`, `nfb_classifier.dart:26-33`, `emotions_classifier.dart:22-28`, `physio_classifier.dart:31-37`) carries a `## Lifecycle` paragraph that says "Both factory constructors verify that EEG streaming is active on [device]". After Phase 1 this becomes false. The plan only edits the `StateError` message strings; it should also reword these class-doc paragraphs (and the per-factory `/// Throws [StateError] when [device] has not been started yet.` lines) to talk about connect instead of start. Recommend adding a "doc-rot sweep" sub-step inside Phase 1 (or a Task 0 across all six files) to keep public API docs in sync with behavior.

2. **Calibration / utility methods become reachable in the connected-but-not-started state.** After the plan, the productivity screen's buttons (`Start Baseline Calibration`, `Reset Fatigue`) and the physio screen's `startBaselineCalibration` / `importBaselines` actions are reachable as soon as the device is connected, because they're gated by `classifier != null` and the classifier is now non-null in `DeviceUiState.connected`. Whether those native calls behave correctly with no EEG stream flowing is a separate concern — the Capsule SDK doc summary in `neiry_kit/CLAUDE.md` implies calibration needs streaming EEG. This isn't a regression caused by the plan (it's a UX shift), but it's the natural next bug to surface and worth a one-line note in the plan's Context. If the SDK rejects the call, surfacing a meaningful error is preferable to silently hanging the progress bar.

3. **`useCalibrationToggleProvider` is still `ref.watch`-ed in three providers.** Tasks 7/8/9 keep `ref.watch(useCalibrationToggleProvider)` / `ref.watch(useMemsCalibrationToggleProvider)`. The only thing preventing a mid-connection toggle flip is the UI gate in Tasks 13/14. If any future caller flips the toggle programmatically (or a new screen is added without the same gate), the classifier provider will rebuild while connected and re-trigger the Android crash the plan is fixing. Not a blocker for this plan, but a single-line warning in the screen file's gating block (or moving the gate into the provider itself via an assertion) would harden the contract.

4. **Race between Dart `_connected` flag and native BLE connection.** `Device.connect()` flips `_connected = true` immediately after `invokeMethod` dispatches the request (`lib/src/api/device.dart:175`), before the actual BLE link-up event arrives via `connectionStateStream`. The plan's new factory guard therefore admits classifier creation during the early "connecting-on-the-wire" window. Whether the native Capsule SDK accepts a classifier construction call in that window is not visible from the Dart side. Two mitigations are worth considering: (a) gate the classifier provider on `deviceConnectionStateProvider == NeiryConnectionState.connected` instead of (or in addition to) `device != null`, which would defer creation until the native side reports the link is up; or (b) keep the plan as-is and verify on real hardware that early-classifier-create doesn't trip the same SDK abort path. This is the one place where the "Settings: Testing: no" choice is uncomfortable — the fix is empirically validated, and skipping verification leaves the failure mode subtle.

### Wording nitpicks

- Tasks 10–12 instruct "update any doc comment referencing `Device.start()`/`Device.stop()` lifecycle." The Emotions, NFB, and Physio provider doc comments don't actually reference `Device.start()`/`Device.stop()` literally — they say "started-state changes". The instruction is still correct in spirit (rephrase to "connection-state changes"), but the verbatim search-and-replace described in Tasks 7/8/9 won't have a match here. Recommend tweaking the wording in those three tasks to "replace any `started-state` / `start()/stop()` wording with `connection-state` / `connect()/disconnect()`".

- Task 7's doc-comment rewrite list ("calibration toggle is safe to flip only while disconnected, newly-imported calibration takes effect on the next `Device.disconnect()` → `Device.connect()` cycle") is specific to providers that consume `nfbCalibrationProvider` + a calibration toggle — i.e., Cardio / MEMS / Productivity. Plan correctly applies the longer comment only to those (Task 7) and the shorter one to Tasks 8–12.

### Positive Notes

- The plan is unusually precise about exact-string replacements per file, which keeps the change set mechanical and easy to review.
- The decision to gate the toggle on `== DeviceUiState.idle` (rather than `!= DeviceUiState.started`) is the right reading of the new invariant: the classifier's `ref.watch` of the toggle means flipping it post-connect would re-create the singleton.
- Removing `deviceIsStartedProvider` from six providers without removing the provider itself is correct — `device_screen.dart` and `deviceUiStateProvider` still depend on it.
- The commit plan (3 commits aligned to phase boundaries) gives clean reverts if any phase regresses on hardware.

PLAN_REVIEW_PASS
