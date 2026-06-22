# Wire Use-NFB-Calibration toggles into the connect flow

**Date:** 2026-06-22
**Source:** conversation context

## Key Findings

- The "Use NFB Calibration" toggle is a **stub** — it records intent but nothing consumes it. `device_screen._connect()` calls `connect(serial)` with no `nfbData` and never reads the toggle, so every classifier is always built generic.
- The backend exists: `NeiryService.connect({IndividualNfbData? nfbData})` passes calibration into `NfbClassifier(calibration:)`, `_safeProductivityWithCalibration`, `CardioClassifier.withCalibration`, `MEMSClassifier.withCalibration`. The missing piece is the glue from the toggle → `connect`.
- Calibration is a **construction-time** parameter (SDK has no classifier reconfigure/Destroy), which is why the toggle says "Takes effect on next connect" — applying it requires rebuilding the classifiers, i.e. a reconnect.
- **Collapse the two existing toggles into one, and host it on the calibration screen.** Today there are two providers — `useMemsCalibrationToggleProvider` (MEMS) and `useCalibrationToggleProvider` (Productivity/Cardio) — but both apply the *same* `IndividualNfbData`, just to different classifiers. Two switches for one dataset is needless complexity, and they live far from where the calibration is produced. Keep a single `useCalibrationToggleProvider` and move its switch to the **calibration screen** (where the calibration it applies is created); it governs calibration for MEMS + Productivity + Cardio together. Delete `useMemsCalibrationToggleProvider`, the MEMS-screen switch, and the Productivity/Cardio-screen switch. NFB classifier keeps receiving calibration unconditionally (no UI toggle ever governed it).
- The toggle is gated on `nfbCalibrationProvider != null` (disabled until a calibration exists). That provider must survive disconnect for the feature to work across reconnects — see [[30-reset-calibration-ui-state-on-disconnect]] (do not clear it).

## Details

### Current state

`example/lib/services/neiry_service.dart`, `connect()`:
```dart
Future<void> connect(String serial, {bool bipolarChannels = false, IndividualNfbData? nfbData}) async {
  ...
  _nfbData = nfbData;
  _nfb          = NfbClassifier(_device!, calibration: _nfbData);
  _productivity = _nfbData != null ? _safeProductivityWithCalibration(_device!, _nfbData!) : ProductivityClassifier(_device!);
  _cardio       = _nfbData != null ? CardioClassifier.withCalibration(_device!, _nfbData!)  : CardioClassifier(_device!);
  _mems         = _nfbData != null ? MEMSClassifier.withCalibration(_device!, _nfbData!)    : MEMSClassifier(_device!);
}
```
`example/lib/screens/device_screen.dart`, `_connect()` (line ~110): `await ref.read(neiryServiceProvider).connect(serial);` — no calibration args.

`example/lib/providers/nfb_calibration_provider.dart` defines both `useMemsCalibrationToggleProvider` and `useCalibrationToggleProvider`; they are read/set only inside `mems_screen.dart` and `productivity_cardio_screen.dart` (switch display + set). No connect-time consumer.

### Exact change

1. **`NeiryService.connect`** (signature at `neiry_service.dart:111–114`; classifier construction at `:142–153`) — add one `useCalibration` flag, default `false` (preserves current callers/behavior). For reference, the construction lines are: `_nfb` `:142`, `_productivity` `:145–147` (`_safeProductivityWithCalibration` defined at `:491`, else `ProductivityClassifier(_device!)`), `_cardio` `:148–150`, `_mems` `:151–153`:
   ```dart
   Future<void> connect(
     String serial, {
     bool bipolarChannels = false,
     IndividualNfbData? nfbData,
     bool useCalibration = false,
   }) async {
     ...
     _nfbData = nfbData;
     final cal = useCalibration ? nfbData : null;

     _nfb          = NfbClassifier(_device!, calibration: nfbData); // unchanged: NFB always uses calibration if present
     _productivity = cal != null ? _safeProductivityWithCalibration(_device!, cal) : ProductivityClassifier(_device!);
     _cardio       = cal != null ? CardioClassifier.withCalibration(_device!, cal)  : CardioClassifier(_device!);
     _mems         = cal != null ? MEMSClassifier.withCalibration(_device!, cal)    : MEMSClassifier(_device!);
   }
   ```
   Keep `_nfbData = nfbData` for the `connect`-error reset path. NFB classifier behavior is intentionally unchanged (no UI toggle governs it).

2. **`device_screen._connect()`** (`device_screen.dart:102`; the `connect(serial)` call to change is at `:110`) — read the single toggle + data and pass them:
   ```dart
   final nfbData = ref.read(nfbCalibrationProvider);
   final useCal  = ref.read(useCalibrationToggleProvider);
   await ref.read(neiryServiceProvider).connect(serial, nfbData: nfbData, useCalibration: useCal);
   ```
   Add `import '../providers/nfb_calibration_provider.dart';` — `device_screen.dart` does NOT currently import it (its imports are `device_screen.dart:8–13`; `calibration_provider.dart` at `:10`, `device_state_providers.dart` at `:12`). Use `ref.read` (one-shot at connect), not `watch`.

3. **Collapse to one toggle, host it on the calibration screen:**
   - `nfb_calibration_provider.dart` — delete `useMemsCalibrationToggleProvider` (`:16`); keep `useCalibrationToggleProvider` (`:21`) and `nfbCalibrationProvider` (`:10`).
   - `calibration_screen.dart` — add a `SwitchListTile` "Use NFB Calibration" inside `_CalibrationDataCard` (`ConsumerWidget` at `:333`, already reads `calibrationProvider` at `:338`) or as its own card below the `_CalibrationDataCard()` slot (`:28`). Watch `nfbCalibrationProvider` + `useCalibrationToggleProvider`; `value: useCal && nfbData != null`; `onChanged: null` while `nfbData == null` (subtitle "Run calibration first to enable"), else sets `useCalibrationToggleProvider` (subtitle "Applies to Productivity, Cardio & MEMS — takes effect on next connect"). Add `import '../providers/nfb_calibration_provider.dart';` — NOT currently imported (imports at `calibration_screen.dart:5–10`).
   - `productivity_cardio_screen.dart` — remove its `SwitchListTile` (`:64`) and the `nfbCalibrationProvider` (`:54`) / `useCalibrationToggleProvider` (`:55`) reads; remove the now-unused `import '../providers/nfb_calibration_provider.dart';` (`:7`).
   - `mems_screen.dart` — remove its `SwitchListTile` (`:28`) and the `nfbCalibrationProvider` (`:17`) / `useMemsCalibrationToggleProvider` (`:18`) reads; remove the now-unused `import '../providers/nfb_calibration_provider.dart';` (`:7`). Keep `import '../providers/device_state_providers.dart';` (`:6`) — still used for the `isConnected` check (`:19–20`).

### Guards / pitfalls

- One toggle, not two — both originally applied the same `IndividualNfbData`; per-group control was needless. Auto-syncing two switches would be more confusing than one.
- Pass `nfbData` even when `useCalibration` is false: NFB classifier still receives it (current behavior). The flag gates only MEMS / Productivity / Cardio.
- Depends on [[30-reset-calibration-ui-state-on-disconnect]] preserving `nfbCalibrationProvider`; depends on [[29-recreate-locator-session-on-disconnect]] so the reconnect that applies the toggle builds a clean session.
- No native changes — pure Dart wiring over existing `withCalibration` constructors.

### Verify

Calibrate → toggle "Use NFB Calibration" on (calibration screen) → Disconnect → Connect → Start. Confirm via logs/behavior that Productivity, Cardio **and** MEMS were constructed with calibration (the `withCalibration` branch taken). Toggling off and reconnecting builds all three generic again. The MEMS and Productivity/Cardio screens no longer show a switch.

## Open Questions

None.

