# Plan: Migrate calibration_screen and CalibrationProvider

## Context
Final migration step of the `NeiryService` refactor: switch `calibration_screen.dart` off the deleted `nfbClassifierProvider` (from the now-gone `nfb_classifier_provider.dart`) onto the stream-based `nfbStateProvider` exposed by `classifier_stream_providers.dart`. `CalibrationNotifier` and `nfbCalibrationProvider` already work against the new architecture and need no changes.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Wire calibration_screen to the new NFB stream provider

- [x] **Task 1: Swap the NFB provider import in `calibration_screen.dart`**
  Files: `example/lib/screens/calibration_screen.dart`
  Replace the line `import '../providers/nfb_classifier_provider.dart';` (line 10) with `import '../providers/classifier_stream_providers.dart';`. `classifier_stream_providers.dart` is the new home of `nfbStateProvider` (see `nfbStateProvider` at line 37 of that file). Keep all other imports (`calibration_provider.dart`, `calibration_timer_provider.dart`, `calibration_ui_state.dart`, `sound_service_provider.dart`) intact — they are still correct after the prior milestones.

- [x] **Task 2: Replace `nfbClassifierProvider` null-check in `_NfbCard.build()`** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  In `_NfbCard.build()` (around lines 276–311), remove `final classifier = ref.watch(nfbClassifierProvider);` and the `classifier == null` branch. Instead, watch `nfbStateProvider` once and render based on its `AsyncValue`:
  - Keep the existing `Card` → `Padding(16)` → `Column` structure with the bold `'NFB Classifier'` title and `SizedBox(height: 8)` spacer.
  - Replace the `if (classifier == null) ... else ref.watch(nfbStateProvider).when(...)` block with a single `ref.watch(nfbStateProvider).when(...)` call.
  - Map the cases to existing UI:
    - `loading: () => const Text('Waiting for device...')` — preserves the pre-data "no device" wording for both the disconnected case (stream empty / not yet emitting) and the post-connect "waiting for first NFB sample" case. The disconnected case is now indistinguishable from "waiting for first sample" because there is no separate classifier handle to inspect, which matches the architecture: `nfbStateProvider` simply has no data until a device is connected and the SDK emits.
    - `error: (e, _) => Text('Error: $e')` — unchanged.
    - `data: (state) => Column(...)` containing the five `_BandRow` widgets for `delta`, `theta`, `alpha`, `smr`, `beta` — unchanged.
  Do not touch `_BandRow`, `_CalibrationCard`, `_CalibrationDataCard`, `_IdleContent`, `_ActiveContent`, `_DoneContent`, or `_ErrorContent` — they are already migrated or unaffected.

### Phase 2: Verify the example app compiles cleanly

- [x] **Task 3: Run `flutter analyze` in `example/` and fix residual import errors** (depends on Task 2)
  Files: any file in `example/lib/` flagged by `flutter analyze`
  From `example/`, run `flutter analyze`. Expected outcome after Task 2: clean. If any file still imports a deleted provider file (`nfb_classifier_provider.dart`, `emotions_classifier_provider.dart`, `physio_classifier_provider.dart`, `cardio_classifier_provider.dart`, `mems_classifier_provider.dart`, `productivity_classifier_provider.dart`, `device_locator_provider.dart`, `active_device_provider.dart`), delete the stale import and replace any symbol references with the equivalents from `classifier_stream_providers.dart`, `neiry_service_provider.dart`, `physio_actions_provider.dart`, or `productivity_actions_provider.dart` as appropriate. Do not modify `calibration_provider.dart` or `nfb_calibration_provider.dart` — the milestone description confirms both are correct as-is. The task is done when `flutter analyze` reports `No issues found!` (or only pre-existing infos unrelated to the deleted providers).
