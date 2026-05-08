## Plan Review: MEMS tab in example app

**Plan file:** `.ai-factory/plans/52-mems-tab-in-example-app.md`
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** WARN — no issues. Plan touches only `example/` files, which correctly depends on `lib/` public API only. `MEMSClassifier` and `MemsSample` are already exported from `neiry_kit.dart`. All dependency rules satisfied.
- **RULES.md:** not present (no file) — WARN, non-blocking.
- **ROADMAP.md:** WARN — the roadmap milestone says "add a 5th tab `/mems`" but the router already has 5 tabs (Device, Streams, Classifiers, Productivity, Calibration), so MEMS is the 6th. The plan itself correctly says "6th tab" — the inconsistency is in the roadmap, not the plan.

### Issues

**1. Copy-paste error in Task 3 — "Cardio Card" label (minor)**

Task 3 describes two Card widgets: "**Accelerometer Card**" and "**Cardio Card** — title 'Gyroscope'". The second should read "**Gyroscope Card**" — "Cardio Card" is a leftover from copying the Productivity+Cardio screen structure. The actual title string `'Gyroscope'` is correct, so the implementer will likely get it right, but the bold label in the plan is misleading.

**2. Missing empty-list guard on `samples.last` (minor)**

Task 3 says to extract `samples.last` from the `data` list. If the list were empty, `.last` throws a `StateError`. The SDK only emits when it has data, so an empty list is unlikely in practice — but the existing codebase guards against this pattern (e.g., `productivity_cardio_screen.dart` line 292: `ppg.values.isNotEmpty ? ... : 'PPG: —'`). The plan should include a `samples.isNotEmpty` check for consistency and defensive correctness.

### Verified Correct

- **Provider pattern**: `MEMSClassifierNotifier extends Notifier<MEMSClassifier?>` with `ref.watch(activeDeviceProvider)`, `ref.watch(deviceIsStartedProvider)`, `ref.watch(nfbCalibrationProvider)`, and a dedicated `useMemsCalibrationToggleProvider` — matches `cardio_classifier_provider.dart` exactly. The decision to use a separate toggle (not share `useCalibrationToggleProvider` from Productivity/Cardio) is correct — MEMS calibration should be independently controllable.
- **Stream provider**: `StreamProvider<List<MemsSample>>` watching `memsClassifierProvider`, returning `Stream.empty()` when null, applying `throttleTime(100ms)` — matches `eegProvider` in `stream_providers.dart`.
- **MEMSClassifier API**: `MEMSClassifier(device)` and `MEMSClassifier.withCalibration(device, nfbData)` match the actual API in `lib/src/api/classifiers/mems_classifier.dart`. The `memsStream` returns `Stream<List<MemsSample>>` — type in the plan is correct.
- **`MemsSample` field access**: `sample.accelerometer.x/y/z` and `sample.gyroscope.x/y/z` via Dart records — matches `lib/src/models/mems_data.dart`.
- **Router insertion**: New branch at index 4 (before Calibration which moves to index 5) is correct. The `NavigationDestination` with `Icons.sensors` and label `'MEMS'` at position 4 matches the branch order.
- **Dispose lifecycle**: `ref.onDispose(() { classifier.dispose(); })` capturing the local classifier instance — matches the established pattern in `cardio_classifier_provider.dart`.
- **File paths**: All referenced files exist or are new files in the correct directories.
- **`nfbCalibrationProvider`**: Correctly imported from `nfb_calibration_provider.dart` — shared cross-tab state, same as Productivity/Cardio.

### Positive Notes

- The plan is well-scoped: 4 tasks, 2 files created, 1 file modified — minimal surface area.
- Correctly separates the MEMS calibration toggle from the shared Productivity/Cardio toggle, preventing unintended coupling.
- The `throttleTime(100ms)` for MEMS display is appropriate — MEMS hardware can fire at high rates, and 10 Hz is sufficient for visual readout.
- Following the existing `NotifierProvider + StreamProvider` pattern keeps the example app consistent.

PLAN_REVIEW_PASS
