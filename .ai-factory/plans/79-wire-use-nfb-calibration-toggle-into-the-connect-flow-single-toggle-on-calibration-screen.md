# Plan: Wire Use-NFB-Calibration toggle into the connect flow (single toggle on calibration screen)

## Context
Make the "Use NFB Calibration" toggle functional by collapsing two redundant toggles into one hosted on the calibration screen, adding a `useCalibration` gate to `NeiryService.connect`, and wiring `device_screen._connect()` to read the toggle + calibration data and pass them at connect time. Pure Dart, no native changes.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Backend gate + provider cleanup

- [x] **Task 1: Add `useCalibration` gate to `NeiryService.connect`**
  Files: `example/lib/services/neiry_service.dart`
  Add a `bool useCalibration = false` parameter to the `connect` signature (currently `connect(String serial, {bool bipolarChannels = false, IndividualNfbData? nfbData})` at lines ~111–115). Default `false` preserves existing callers. Keep `_nfbData = nfbData` (line ~123) for the connect-error reset path. In the classifier construction block (lines ~142–153), introduce `final cal = useCalibration ? nfbData : null;` and gate the three classifiers on `cal`:
  - `_nfb` (line ~142) — UNCHANGED: keeps `calibration: nfbData` (NFB always uses calibration if present; no UI toggle governs it).
  - `_productivity` (lines ~145–147) — `cal != null ? _safeProductivityWithCalibration(_device!, cal) : ProductivityClassifier(_device!)`.
  - `_cardio` (lines ~148–150) — `cal != null ? CardioClassifier.withCalibration(_device!, cal) : CardioClassifier(_device!)`.
  - `_mems` (lines ~151–153) — `cal != null ? MEMSClassifier.withCalibration(_device!, cal) : MEMSClassifier(_device!)`.
  Update the doc comment to note `useCalibration` gates MEMS/Productivity/Cardio while NFB always receives calibration. Construction-time only — applies on next connect by design.

- [x] **Task 2: Delete the redundant MEMS toggle provider**
  Files: `example/lib/providers/nfb_calibration_provider.dart`
  Delete `useMemsCalibrationToggleProvider` (line ~16) and its doc comment. Keep `nfbCalibrationProvider` (line ~10) and `useCalibrationToggleProvider` (line ~21). Update `useCalibrationToggleProvider`'s doc comment to reflect that it now governs MEMS + Productivity + Cardio together.

### Phase 2: Host the single toggle on the calibration screen

- [x] **Task 3: Add the "Use NFB Calibration" toggle to the calibration screen** (depends on Task 2)
  Files: `example/lib/screens/calibration_screen.dart`
  Add `import '../providers/nfb_calibration_provider.dart';` (not currently imported; imports are at lines ~5–10). Add a new `SwitchListTile`-based card (a small `ConsumerWidget`, e.g. `_UseCalibrationCard`) and place it in the screen's `Column` (lines ~22–30), below the `_CalibrationDataCard()` slot (line ~28) with a `SizedBox(height: 12)` separator. The widget watches `nfbCalibrationProvider` and `useCalibrationToggleProvider`:
  - `title`: "Use NFB Calibration"
  - `value: useCal && nfbData != null`
  - When `nfbData == null`: `onChanged: null`, subtitle "Run calibration first to enable".
  - When `nfbData != null`: `onChanged` sets `useCalibrationToggleProvider.notifier).state = val`, subtitle "Applies to Productivity, Cardio & MEMS — takes effect on next connect".
  Match the existing switch styling (grey subtitle text) used previously on the MEMS/Productivity screens. Note: the screen's root `Column` is currently `const`; adding a non-const `ConsumerWidget` card requires removing `const` from that `Column`/`SingleChildScrollView` as needed.

### Phase 3: Wire connect + remove old switches

- [x] **Task 4: Wire `device_screen._connect()` to read and pass the toggle** (depends on Task 1, Task 3)
  Files: `example/lib/screens/device_screen.dart`
  Add `import '../providers/nfb_calibration_provider.dart';` (not currently imported; imports at lines ~8–13). In `_connect()` (line ~102), replace the call at line ~110 (`await ref.read(neiryServiceProvider).connect(serial);`) with one-shot reads passed into connect:
  ```dart
  final nfbData = ref.read(nfbCalibrationProvider);
  final useCal = ref.read(useCalibrationToggleProvider);
  await ref.read(neiryServiceProvider).connect(serial, nfbData: nfbData, useCalibration: useCal);
  ```
  Use `ref.read` (one-shot at connect), not `watch`.

- [x] **Task 5: Remove the switch from the Productivity/Cardio screen** (depends on Task 3)
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  Remove the `SwitchListTile` (lines ~63–83) and the following `SizedBox(height: 12)` if it was the toggle's separator. Remove the `nfbData` (line ~54) and `useCalibration` (line ~55) reads from `build`. Remove the now-unused `import '../providers/nfb_calibration_provider.dart';` (line ~7). Update the class doc comment (lines ~47–48) to drop the "shared NFB calibration toggle" mention. Keep `device_state_providers.dart` import (still used).

- [x] **Task 6: Remove the switch from the MEMS screen** (depends on Task 3)
  Files: `example/lib/screens/mems_screen.dart`
  Remove the `SwitchListTile` (lines ~28–48) and its trailing `SizedBox(height: 12)` only if it leaves the remaining layout intact (keep one separator before the data section). Remove the `nfbData` (line ~17) and `useCalibration` (line ~18) reads from `build`. Remove the now-unused `import '../providers/nfb_calibration_provider.dart';` (line ~7). Keep `import '../providers/device_state_providers.dart';` (line ~6) — still used for the `isConnected` check (lines ~19–20). Update the class doc comment (lines ~10–11) to drop the toggle mention.

## Commit Plan
- **Commit 1** (after tasks 1-6): "Wire Use NFB Calibration toggle into connect flow via single calibration-screen switch"

> Single commit: the changes are interdependent — deleting `useMemsCalibrationToggleProvider` (Task 2) breaks `mems_screen.dart` until Task 6, so the set must land together to keep the build green.
