## Plan Review: Physio + Emotions Tab

**Plan file:** `.ai-factory/plans/50-physio-emotions-tab.md`
**Files reviewed:** 15 (plan + referenced source files)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** PASS — All new files land in `example/lib/providers/` and `example/lib/screens/`, consistent with the architecture's `example/` structure. The example app only imports from the barrel `neiry_kit.dart`, respecting the dependency rule `example/ -> lib/ public API only`.
- **RULES.md:** WARN — File does not exist.
- **ROADMAP.md:** PASS — The plan implements the unchecked `Physio + Emotions tab` milestone. The prerequisite `PhysiologicalStatesBaselines model + PhysioClassifier fix` milestone is already checked `[x]`.

### Critical Issues

None.

### Issues

**1. Side-effect mechanism for `physioBaselinesProvider` is unspecified (Task 1)**

Task 1 says `physioCalibratedProvider` (a `StreamProvider`) should "also write the value to a `physioBaselinesProvider`" when it emits. However, a `StreamProvider` in Riverpod is declarative — it has no built-in hook to fire imperative side-effects on emission.

The implementer must choose a mechanism:
- (a) Side-effect inside `.map()` on the stream — works but is an anti-pattern in Riverpod (impure stream transformation).
- (b) `ref.listen(physioCalibratedProvider, ...)` inside `PhysioClassifierNotifier.build()` — cleaner, keeps the write in the provider layer.
- (c) Widget-level write inside `.when(data:)` in `_PhysioCard` — Task 5 already hints at this ("When `physioCalibratedProvider` emits, show a brief 'Baselines calibrated' confirmation and write to `physioBaselinesProvider`").

Option (b) is the most consistent with codebase conventions (`calibration_provider.dart` does imperative writes to `nfbCalibrationProvider` from the notifier, not from StreamProviders or widgets). Recommend the plan specify this explicitly.

Severity: **Low** — the plan follows correct patterns overall and an implementer familiar with the codebase would resolve this, but explicit wording avoids ambiguity.

**2. Redundant `physioBaselinesProvider` write in Task 5 import flow**

Task 1 defines `importBaselines()` on the notifier as: "delegates to `classifier.importBaselines(baselines)` and writes to `physioBaselinesProvider`." Task 5 then says the Import button "calls `ref.read(physioClassifierProvider.notifier).importBaselines(result)` **and writes to `physioBaselinesProvider`**." The notifier method already handles the write — the widget shouldn't duplicate it.

Recommendation: Remove "and writes to `physioBaselinesProvider`" from Task 5's Import button description, since the notifier method already handles it.

Severity: **Low** — redundant but not harmful (double-writing the same value is idempotent).

**3. Missing try/catch around Import button in Task 5**

The Import button calls `PhysioBaselinesFileManager.importFromFile()` then `importBaselines(result)`. If the JSON file is malformed, `jsonDecode` or `fromMap` will throw. The plan doesn't specify error handling — no try/catch, no error SnackBar.

The existing `CalibrationNotifier.importFromFile()` wraps the entire operation in try/catch (lines 116-124 of `calibration_provider.dart`). The plan should either:
- Wrap the import logic in a notifier method with try/catch (matching the calibration pattern), or
- Specify try/catch at the widget level with a SnackBar for errors.

Severity: **Low** — example app code, but unhandled exceptions would crash the UI on bad input files.

### Verified Assumptions

- `PhysioClassifier` API: `stateStream` returns `Stream<PhysiologicalStatesValue>`, `calibrationProgress` returns `Stream<double>`, `calibrated` returns `Stream<PhysiologicalStatesBaselines>`, `startBaselineCalibration()` and `importBaselines(PhysiologicalStatesBaselines)` exist. All confirmed in `lib/src/api/classifiers/physio_classifier.dart`.
- `EmotionsClassifier` API: `stateStream` returns `Stream<EmotionsStates>`, no calibration methods. Confirmed in `lib/src/api/classifiers/emotions_classifier.dart`.
- `PhysiologicalStatesValue` fields: `relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress` (all `double?`), `nfbArtifacts`, `cardioArtifacts` (both `bool`), `timestamp` (`DateTime`). Confirmed in `lib/src/models/physio_states.dart`.
- `EmotionsStates` fields: `attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl` (all `double?`), `timestamp` (`DateTime`). Confirmed in `lib/src/models/emotions_states.dart`.
- `PhysiologicalStatesBaselines` has `toMap()` and `fromMap()`. Confirmed in `lib/src/models/physio_baselines.dart`.
- The two-layer provider pattern (`NotifierProvider` + `StreamProvider`) matches `nfb_classifier_provider.dart` exactly.
- The `CalibrationFileManager` pattern with `exportToFile`/`importFromFile` as `abstract final class` with static methods is confirmed.
- `_BandRow` helper widget exists in `calibration_screen.dart` (line 270) and matches the described pattern.
- `activeDeviceProvider` returns `Device?`, `deviceIsStartedProvider` returns `bool` — both confirmed.
- `ClassifiersScreen` is currently a stub `StatelessWidget` — confirmed, safe to replace.
- All file paths in the plan are valid and consistent with codebase layout.
- `file_picker`, `path_provider` are already in `example/pubspec.yaml` — no new dependencies needed.
- `StatefulShellRoute.indexedStack` keeps all tab widgets mounted — physio's ~2-minute update cadence won't lose state on tab switches.

### Positive Notes

- The plan correctly follows all established codebase patterns (two-layer providers, file manager, `_BandRow` helper, `ref.onDispose` with captured local instance).
- Good UX design for the 2-minute Physio update cadence: opacity reduction + "Waiting for first update" + "Last updated" timestamp. Avoids noisy countdown.
- Correctly skips the `none` field from Physio display — it's an SDK internal placeholder, not a user-facing metric.
- Manual timestamp formatting avoids adding the `intl` package dependency.
- Clear task dependency chain (Phase 1 providers before Phase 2 UI).
- Correctly separates Emotions (continuous, no timestamp) from Physio (2-min cadence, timestamp + signal quality + baselines) into distinct cards.

PLAN_REVIEW_PASS
