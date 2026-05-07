## Code Review Summary

**Files Reviewed:** 7 (6 new + 1 modified)
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — no violations. All new files live in `example/` and depend only on the `neiry_kit` barrel export. Provider patterns (`AsyncNotifier`, `Notifier`, `StateProvider`, `StreamProvider`) follow established conventions in the codebase.
- **RULES.md:** file does not exist, skipped.
- **ROADMAP.md:** WARN — milestone specifies `CalibrationTimerNotifier` as `StateNotifier`, but implementation correctly uses `Notifier` (modern Riverpod). Functionally identical, strictly better. Non-blocking.

### Critical Issues

None.

### Issues

1. **Race condition between `abort()` and `startFull()` state writes** (`calibration_provider.dart`)

   When the user presses "Abort" during a full calibration, both `abort()` and `startFull()` write to `state` asynchronously:
   - `abort()` completes `_fullCompleter` with error, then awaits `WakelockPlus.disable()` and `NfbCalibrator.getCalibrationData()`, then writes `AsyncValue.data(...)`.
   - `startFull()` catches the error via `AsyncValue.guard`, runs its `finally` block (`WakelockPlus.disable()`), then writes `AsyncValue.error(...)`.

   The final visible state depends on which `await` chain resolves last. If `startFull()`'s guard finishes after `abort()` sets the data state, the user sees a `CalibrationError('Calibration aborted')` instead of the expected idle/data state after pressing Abort.

   **Suggested fix:** Add a boolean flag `_aborted` that `abort()` sets before completing the completer. After `AsyncValue.guard` in `startFull()`, check `if (_aborted) return;` to skip the state write:
   ```dart
   // In startFull(), after the guard:
   if (_aborted) return; // abort() already set the correct state
   state = await AsyncValue.guard(...);
   _writeToSharedProvider();
   ```

2. **Unhandled exceptions in `importFromFile()`** (`calibration_provider.dart:108-114`, `calibration_screen.dart:112-113`)

   If the user picks a malformed JSON file (invalid syntax, missing keys, wrong types), `CalibrationFileManager.importFromFile()` throws at `jsonDecode` or `IndividualNfbData.fromMap`. This exception propagates uncaught from `CalibrationNotifier.importFromFile()`. The button handler fires the future without catching:
   ```dart
   onPressed: () => ref.read(calibrationProvider.notifier).importFromFile(),
   ```
   Result: unhandled async error, no user feedback.

   **Suggested fix:** Wrap the body of `CalibrationNotifier.importFromFile()` in a try/catch and set `state = AsyncError(...)` on failure, or wrap the file-parsing section in `CalibrationFileManager.importFromFile()` with a try/catch that returns `null` for unparseable files.

### Positive Notes

- Clean sealed class design for `CalibrationUiState` — exhaustive `switch` in the UI catches all states at compile time.
- `NfbClassifierNotifier.build()` correctly captures the classifier in a local variable for `ref.onDispose`, avoiding the stale-state-in-dispose-callback footgun called out in the plan.
- Stage advance guard `if (stage.code < 3)` with `CalibrationStage.fromCode(stage.code + 1)` is safe — no index-out-of-bounds risk.
- `ScaffoldMessenger.of(context)` captured before the async gap in the export button handler — correct Flutter pattern.
- `CalibrationFileManager` extraction keeps file I/O testable and the notifier focused on state management.
- `nfbCalibrationProvider` as simple `StateProvider` is the right call — no custom notifier logic needed.
- Timer cleanup via `ref.onDispose` in `CalibrationTimerNotifier.build()` follows the `ResistanceMapNotifier` pattern correctly.
- Wakelock enable/disable bracketing with `try/finally` in both `startFull()` and `startQuick()` ensures the screen stays awake during calibration and is released on both success and error paths.
