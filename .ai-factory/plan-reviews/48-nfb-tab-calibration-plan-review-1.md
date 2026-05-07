## Plan Review: NFB tab + calibration

**Files in Plan:** 7 new/modified
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** WARN — no violations. All new files are in `example/` and depend only on the `neiry_kit` barrel export. Provider patterns follow existing conventions (`Notifier`, `AsyncNotifier`, `StateProvider`, `StreamProvider`). The plan does not touch `lib/` (plugin API layer).
- **RULES.md:** file does not exist, skipped.
- **ROADMAP.md:** WARN — the roadmap milestone says `nfbCalibrationProvider` is `StateNotifierProvider<IndividualNfbData?>`, but the plan simplifies to `StateProvider<IndividualNfbData?>`. Functionally equivalent and the simpler choice since no custom notifier logic is needed. Downstream milestone (Productivity + Cardio tab) references `StateNotifierProvider` — the implementer of that milestone will need to match whichever type is actually created here. Non-blocking.

### Critical Issues

None found.

### Observations (non-blocking)

1. **Task 2 — misleading `ResistanceMapNotifier` reference.** The plan says "Follow the `ResistanceMapNotifier` pattern from `stream_providers.dart` for `StateNotifier` + `ref.onDispose` conventions" — but `ResistanceMapNotifier` extends `Notifier`, not `StateNotifier`. The clarification that follows ("here `StateNotifierProvider` manages its own `dispose()` lifecycle automatically") resolves the ambiguity. An implementer reading only the reference might pick the wrong base class before reading the full sentence.

2. **`importFromFile()` — `nfbCalibrationProvider` write.** The plan text correctly says to write to `nfbCalibrationProvider` after import. The explore note code snippet at `14-explore-example-calibration-ui.md` omits this write. Since the plan text is the authority, the implementation should follow it. Mentioning this so the implementer doesn't copy the explore note code verbatim.

3. **`importFromFile()` / `exportToFile()` — no error handling.** Neither method wraps its I/O in try/catch. A malformed JSON file, missing file path, or permission denial would produce an unhandled exception. For an example app this is acceptable, but wrapping in `AsyncValue.guard` (for import) or a try/catch with a snackbar (for export) would be more robust.

4. **`abort()` during `startFull()` — state ordering.** When `abort()` is called while `startFull()`'s `AsyncValue.guard` is pending: (a) abort completes the completer with error, (b) the guard catches the error and sets `state = AsyncValue.error(...)`, (c) then abort's final line sets `state = AsyncValue.data(...)`. The final state is correct (data from `getCalibrationData()`), but there is a brief flicker through the error state. Cosmetic only — the UI will settle on the correct state within the same frame or next frame.

5. **Double `WakelockPlus.disable()` on abort.** The `finally` block in `startFull()`'s guard and `abort()` itself both call `WakelockPlus.disable()`. Wakelock plus is idempotent, so this is harmless.

### Verification Notes

- **Stage guard is correct.** `if (stage.code < 3)` prevents an out-of-bounds `fromCode(4)` when `CalibrationStageFinished(stage4)` fires. The plan explicitly rejects the explore note's `CalibrationStage.values[stage.index + 1]` pattern which would crash on stage 4.
- **`fromCode` vs array indexing.** The plan uses `CalibrationStage.fromCode(stage.code + 1)` — safe because `fromCode` throws `ArgumentError` on unknown codes rather than silently producing a wrong value. Correct.
- **Native stop on abort.** Cancelling `_sub` (the subscription to `calibrateIndividual()`'s stream) triggers the `StreamController.onCancel` inside `NfbCalibrator`, which calls `stopCalibration` on the native side. No separate `NfbCalibrator.stopCalibration()` call needed in `abort()`.
- **`AsyncNotifier.build()` cleanup.** `ref.onDispose` registered inside `build()` is the correct pattern — Riverpod fires it before the next `build()` and on final disposal.
- **`NfbClassifierNotifier` captures classifier locally in `onDispose`.** Correct — avoids reading `state` inside the dispose callback, which could return a different (or disposed) classifier.
- **All dependencies present.** `file_picker`, `path_provider`, `wakelock_plus`, `riverpod`, `flutter_riverpod` are already in `example/pubspec.yaml`.
- **`IndividualNfbData.fromMap` accepts `Map<String, dynamic>`.** `jsonDecode` returns `Map<String, dynamic>` which is a runtime subtype of `Map<Object?, Object?>` via Dart's covariant generics. No cast issue.
- **Quick calibration has no abort button.** UI maps quick-loading (no timer stage) to a generic loading indicator with no abort button. Acceptable — quick calibration is single-stage and fast.

### Positive Notes

- Plan explicitly corrects the explore note's out-of-bounds bug on stage 4 and the incorrect `dispose()` override on `AsyncNotifier`.
- Wakelock management uses `try/finally` consistently — covers both success and error paths.
- `CalibrationUiState` sealed class keeps instruction text and stage labels co-located with state, preventing stringly-typed UI logic.
- Task 7 extracts file I/O into a separate helper class, keeping the notifier focused on state management.
- The completer pattern for bridging a stream-based calibration API to an `AsyncNotifier` is well-designed — clean separation between the event listener and the state update.
- Cross-tab shared state via `nfbCalibrationProvider` is the minimal correct solution for downstream consumers (Productivity, Cardio).

PLAN_REVIEW_PASS
