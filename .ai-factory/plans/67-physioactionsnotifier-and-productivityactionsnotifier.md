# Plan: PhysioActionsNotifier and ProductivityActionsNotifier

## Context
Introduce two command-only Riverpod notifiers that own classifier action invocations (baseline calibration, baseline import, fatigue reset) by delegating to the `NeiryService` classifier handles. This separates "command" responsibilities from the data-stream providers and unblocks screen migration in the next milestone.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Action notifiers

- [x] **Task 1: Create `PhysioActionsNotifier`**
  Files: `example/lib/providers/physio_actions_provider.dart`
  Create a new file declaring `PhysioActionsNotifier extends Notifier<void>` and a matching provider `physioActionsProvider = NotifierProvider<PhysioActionsNotifier, void>(PhysioActionsNotifier.new)`. The `build()` method does nothing (returns `void`). Add two instance methods:
  - `Future<void> startBaselineCalibration()` — reads `neiryServiceProvider` via `ref.read`, then calls `physioClassifier?.startBaselineCalibration()` and awaits it when non-null. If `physioClassifier` is null, return without error (no active device).
  - `Future<void> importBaselines(PhysiologicalStatesBaselines baselines)` — reads `neiryServiceProvider`, calls `physioClassifier?.importBaselines(baselines)` and awaits it; on success (i.e. when `physioClassifier` was non-null) write `baselines` into `physioBaselinesProvider` via `ref.read(physioBaselinesProvider.notifier).state = baselines`. Do not update the provider when the classifier is null.
  Imports: `package:flutter_riverpod/flutter_riverpod.dart`, `package:neiry_kit/neiry_kit.dart` (for `PhysiologicalStatesBaselines`), `neiry_service_provider.dart`, `classifier_stream_providers.dart` (for `physioBaselinesProvider`). Follow the existing provider style in `example/lib/providers/` (lowerCamelCase provider names, no part files). SRP: this notifier owns only commands — no state, no streams.

- [x] **Task 2: Create `ProductivityActionsNotifier`** (depends on Task 1)
  Files: `example/lib/providers/productivity_actions_provider.dart`
  Create a new file declaring `ProductivityActionsNotifier extends Notifier<void>` and a matching provider `productivityActionsProvider = NotifierProvider<ProductivityActionsNotifier, void>(ProductivityActionsNotifier.new)`. The `build()` method does nothing. Add two instance methods:
  - `Future<void> startBaselineCalibration()` — reads `neiryServiceProvider`, then `await productivityClassifier?.startBaselineCalibration()`. Null classifier = no-op.
  - `Future<void> resetAccumulatedFatigue()` — reads `neiryServiceProvider`, then `await productivityClassifier?.resetAccumulatedFatigue()`. Null classifier = no-op.
  Imports: `package:flutter_riverpod/flutter_riverpod.dart`, `neiry_service_provider.dart`. No screen wiring or other behavior — matches the SRP statement in the milestone description (commands to classifier only). Do not write any state and do not touch `physioBaselinesProvider`.

## Notes
- Screen wiring (replacing `physioClassifierProvider.notifier.startBaselineCalibration()` etc. with the new `physioActionsProvider`/`productivityActionsProvider`) is intentionally **not** in this milestone — it is task 93 in `ROADMAP.md`. This milestone only creates the two notifier files.
- `PhysioClassifier.importBaselines` takes `PhysiologicalStatesBaselines` (typed model), matching the signature called from `classifiers_screen.dart` line 177.
- `ProductivityClassifier.importBaselines` exists but takes a `Uint8List` and is **not** part of this milestone — only `startBaselineCalibration` and `resetAccumulatedFatigue` per the description.
- Both notifiers must use `ref.read(neiryServiceProvider)` (not `watch`) — these are one-shot command invocations, not reactive subscriptions, so they must not rebuild when the service identity changes.
- `physioBaselinesProvider` is a `StateProvider<PhysiologicalStatesBaselines?>` already declared in `example/lib/providers/classifier_stream_providers.dart` (line 65); reuse it as-is.
