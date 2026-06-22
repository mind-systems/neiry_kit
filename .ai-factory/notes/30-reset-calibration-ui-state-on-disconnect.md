# Reset calibration UI state on disconnect

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- After a disconnect the calibration screen still shows the previous run's "calibrated" state (peak frequency, band, "Status: valid"). The state is cached in Riverpod and never reset when the device drops.
- **Reset only `calibrationProvider`, NOT `nfbCalibrationProvider`.** These two are different concerns:
  - `calibrationProvider` (`AsyncNotifierProvider<CalibrationNotifier, IndividualNfbData?>`) reflects the live SDK calibrator state — the session forgets it on disconnect, so the screen must return to idle.
  - `nfbCalibrationProvider` (`StateProvider<IndividualNfbData?>`) holds the **portable** `IndividualNfbData` numbers (exportable/importable, session-independent). It is the input the "Use NFB Calibration" toggles consume on the next connect (see [[32-wire-use-nfb-calibration-toggle-into-connect]]). Wiping it on disconnect would disable that feature after every reconnect, so it must survive.
- The connection state is already available app-wide via `deviceConnectionStateProvider` (`StreamProvider<NeiryConnectionState>`), which emits `NeiryConnectionState.disconnected` on disconnect (the service synthesizes it). The calibration notifier can watch it and clear itself.
- This is independent of the native locator-session fix ([[29-recreate-locator-session-on-disconnect]]) — that fixes the SDK so re-calibration works; this fixes the displayed state.

## Details

### Current state

`example/lib/providers/calibration_provider.dart`:
- `CalibrationNotifier extends AsyncNotifier<IndividualNfbData?>`; `build()` registers `ref.onDispose(...)` and returns `NfbCalibrator.getCalibrationData()`. It does not watch connection state.
- `_writeToSharedProvider()` pushes the result into `nfbCalibrationProvider` after a run/import.

`example/lib/providers/device_state_providers.dart`:
- `deviceConnectionStateProvider = StreamProvider<NeiryConnectionState>((ref) => ref.watch(neiryServiceProvider).connectionStateStream);`

`example/lib/screens/calibration_screen.dart`:
- `_CalibrationCard` derives its UI from `calibrationProvider` (`CalibrationDone` when `value != null`). `_CalibrationDataCard` reads `calibrationProvider.value` directly. So clearing `calibrationProvider` to `data(null)` returns the card to `CalibrationIdle` and blanks the data card.

### Exact change

In `CalibrationNotifier.build()` (`calibration_provider.dart:40–45` — insert after the `ref.onDispose(...)` block at `:41–44`, before `return NfbCalibrator.getCalibrationData();` at `:45`):
```dart
// Reset the on-screen calibration state when the device disconnects so the UI
// does not keep showing the previous session's "calibrated" result. Pairs with
// the native locator-session reset that makes the SDK forget the old calibration.
// Do NOT clear nfbCalibrationProvider — that holds the portable IndividualNfbData
// the "Use NFB Calibration" toggles apply on the next connect.
ref.listen(deviceConnectionStateProvider, (prev, next) {
  if (next.valueOrNull == NeiryConnectionState.disconnected) {
    state = const AsyncValue.data(null);
  }
});
```
Add `import 'device_state_providers.dart';` to the imports block (`calibration_provider.dart:8–10`, same `providers/` dir). `deviceConnectionStateProvider` is defined at `device_state_providers.dart:8` as `StreamProvider<NeiryConnectionState>`. `NeiryConnectionState.disconnected` is already in scope via `import 'package:neiry_kit/neiry_kit.dart';` (`calibration_provider.dart:5`).

### Guards / pitfalls

- Use `next.valueOrNull` — `deviceConnectionStateProvider` is async; ignore loading/error frames.
- Setting `state` inside an `AsyncNotifier` is valid. Do not `ref.invalidate(calibrationProvider)` here — that re-runs `getCalibrationData()` against a torn-down/absent device and can surface an error frame; setting `data(null)` is the clean idle reset.
- **Do not clear `nfbCalibrationProvider`** — it is portable saved calibration data, not live SDK state. Clearing it breaks [[32-wire-use-nfb-calibration-toggle-into-connect]].
- Do not reset on `connecting`/`connected` transitions — only `disconnected`.

### Verify

Connect → calibrate (card shows "calibration complete / valid" and the data card shows peak/band) → Disconnect. Expect the calibration card to return to idle ("Start Full/Quick Calibration") and the data card to blank, while the "Use NFB Calibration" toggles on the MEMS / Productivity screens stay enabled (their `nfbCalibrationProvider` data is preserved).

## Open Questions

None.
