## Code Review: Physio + Emotions Tab

**Plan:** `.ai-factory/plans/50-physio-emotions-tab.md`
**Files reviewed:** 4 implementation files + 6 reference files
**Risk Level:** Low

### Critical Issues

None.

### Issues

**1. Unhandled exceptions in Import Baselines button callback**

File: `example/lib/screens/classifiers_screen.dart:164-175`

The Import button calls `PhysioBaselinesFileManager.importFromFile()` directly in an `onPressed` async callback with no try/catch. If the selected file contains malformed JSON, `jsonDecode` throws `FormatException`. If the file contains valid JSON but wrong shape, `fromMap` throws a cast error. Either will be an unhandled exception that surfaces as a red-screen crash.

The reference pattern in `calibration_provider.dart:115-125` wraps the equivalent import in try/catch:
```dart
Future<void> importFromFile() async {
  try {
    final data = await CalibrationFileManager.importFromFile();
    ...
  } catch (e, st) {
    state = AsyncValue.error(e, st);
  }
}
```

Fix: wrap the import callback body in try/catch and show an error SnackBar:
```dart
onPressed: () async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await PhysioBaselinesFileManager.importFromFile();
    if (result != null) {
      await ref.read(physioClassifierProvider.notifier).importBaselines(result);
      messenger.showSnackBar(const SnackBar(content: Text('Baselines imported')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
},
```

Severity: **Medium** — runtime crash on bad input file.

**2. Unhandled exceptions in Export Baselines button callback**

File: `example/lib/screens/classifiers_screen.dart:186-193`

Same pattern: `PhysioBaselinesFileManager.exportToFile(baselines)` can throw on I/O failure (disk full, permission denied). No try/catch in the callback.

Fix: wrap in try/catch with error SnackBar, same as above.

Severity: **Low** — export is less likely to fail than import, but still unguarded.

**3. Side-effect in stream `.map()` is a Riverpod anti-pattern**

File: `example/lib/providers/physio_classifier_provider.dart:85-88`

```dart
return classifier.calibrated.map((baselines) {
  ref.read(physioBaselinesProvider.notifier).state = baselines;
  return baselines;
});
```

Writing to another provider inside a `.map()` stream transformation is impure. It works correctly here because `physioCalibratedProvider` is always subscribed via `ref.listen` in `_PhysioCard`, but the behavior is fragile — if `physioCalibratedProvider` is ever removed from the widget tree without a subscriber, the side-effect silently stops firing and baselines are never persisted.

The cleaner pattern (matching how `calibration_provider.dart` writes to `nfbCalibrationProvider`) is `ref.listen` inside the notifier's `build()`:

```dart
// Inside PhysioClassifierNotifier.build(), after creating the classifier:
ref.listen(physioCalibratedProvider, (_, next) {
  if (next.hasValue && next.value != null) {
    ref.read(physioBaselinesProvider.notifier).state = next.value!;
  }
});
```

Then `physioCalibratedProvider` becomes a plain pass-through with no side-effect.

Severity: **Low** — functionally correct in current wiring, but brittle for future changes.

### Verified Correctness

- `EmotionsClassifierNotifier` follows the `NfbClassifierNotifier` pattern exactly: gates on `activeDeviceProvider`/`deviceIsStartedProvider`, captures local classifier for `ref.onDispose`, returns null when conditions not met.
- `PhysioClassifierNotifier` extends the same pattern with `startBaselineCalibration()` and `importBaselines()` methods, both correctly null-safe via `state?.`.
- `importBaselines` correctly writes to `physioBaselinesProvider` so the export button enables.
- `PhysioBaselinesFileManager` mirrors `CalibrationFileManager` 1:1 — same `abstract final class`, same `FilePicker` + `path_provider` flow, same `jsonEncode(model.toMap())` / `jsonDecode + fromMap()` round-trip.
- `_EmotionsCard` displays all 5 `EmotionsStates` fields (attention, relaxation, cognitiveLoad, cognitiveControl, selfControl). No timestamp — correct per requirements.
- `_PhysioCard` displays 5 of 6 `PhysiologicalStatesValue` fields (correctly skips `none` — internal SDK placeholder).
- Signal quality section correctly maps `nfbArtifacts`/`cardioArtifacts` bools to green check_circle (false = good) / red error (true = bad).
- "Last updated: HH:MM:SS" uses manual formatting avoiding an `intl` dependency.
- `Opacity(opacity: 0.5)` applied during loading state communicates the ~2-minute wait.
- Calibration progress `LinearProgressIndicator` visible only when `physioCalibrationProgressProvider` has data — hidden via `whenOrNull` + null coalescing during idle.
- Export button disabled when `physioBaselinesProvider` is null — correct gating.
- `ref.listen(physioCalibratedProvider, ...)` in `_PhysioCard` shows "Baselines calibrated" SnackBar — lifecycle-managed by Riverpod, no leak risk.
- `ScaffoldMessenger.of(context)` captured before async gap in all button callbacks — correct pattern preventing use-after-dispose.
- `_MetricRow` label width (140) accommodates longer labels like "Cognitive Control" — appropriate divergence from `_BandRow`'s 60.
- All providers use `Stream.empty()` when classifier is null — StreamProvider stays in loading, no errors.
- `StatefulShellRoute.indexedStack` keeps classifiers tab mounted — physio's ~2-minute update cadence survives tab switches.
- `physioBaselinesProvider` uses `StateProvider` from `flutter_riverpod/legacy.dart` — correct import for Riverpod 3.x.
- `exportToFile` returns `Future<File>` (non-nullable) vs CalibrationFileManager's `Future<File?>` — more accurate since the method never returns null; the nullable return in the reference was vestigial.

REVIEW_PASS
