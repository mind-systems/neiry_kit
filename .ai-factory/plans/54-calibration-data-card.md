# Plan: Calibration data card

## Context
Add a third card to `CalibrationScreen` that displays the `IndividualNfbData` produced by the calibration provider, mirroring the layout of the existing `_NfbCard`. Default-constructed `IndividualNfbData` is used as the pre-calibration placeholder, so the card always renders concrete values.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Implementation

- [x] **Task 1: Add `_CalibrationDataCard` widget**
  Files: `example/lib/screens/calibration_screen.dart`
  In `example/lib/screens/calibration_screen.dart`, add a new private `_CalibrationDataCard extends ConsumerWidget` class at the bottom of the file (after `_BandRow`). Its `build` method must:
  - Watch `calibrationProvider` (already imported from `../providers/calibration_provider.dart`).
  - Derive display data as `final data = ref.watch(calibrationProvider).value ?? const IndividualNfbData();` — the default-constructed `IndividualNfbData` (defaults: `individualFrequency: 10.0`, `lowerFrequency: 7.0`, `upperFrequency: 13.0`, `individualBandwidth: 6.0`, `individualNormalizedPower: 0.5`) acts as the pre-calibration placeholder.
  - Add the import `import '../../lib/...'` only if `IndividualNfbData` is not already accessible through `calibration_provider.dart`'s re-exports. Verify the actual public package import path (e.g. `package:neiry_kit/neiry_kit.dart`) used by other screens/providers in the example app and reuse the same import style.
  - Return a `Card` containing `Padding(const EdgeInsets.all(16))` wrapping a `Column(crossAxisAlignment: CrossAxisAlignment.start)`, identical in structure to `_NfbCard`.
  - First child: `const Text('Individual Alpha', style: TextStyle(fontWeight: FontWeight.bold))`.
  - Followed by `const SizedBox(height: 8)` (mirroring `_NfbCard`).
  - Then five `_BandRow` rows, in this exact order:
    1. `_BandRow('Peak, Hz', data.individualFrequency)`
    2. `_BandRow('Lower, Hz', data.lowerFrequency)`
    3. `_BandRow('Upper, Hz', data.upperFrequency)`
    4. `_BandRow('Bandwidth, Hz', data.individualBandwidth)`
    5. `_BandRow('Norm. power', data.individualNormalizedPower)`
  - Do NOT add rows for `individualPeakFrequencyPower` or `individualPeakFrequencySuppression`.
  - Reuse the existing `_BandRow` widget without modification. All values passed in are non-null `double`, so the `—` fallback path will never trigger but remains harmless.

- [x] **Task 2: Insert the new card into `CalibrationScreen.build`** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  In the `Column` returned by `CalibrationScreen.build`, after the existing `_NfbCard()` entry, append:
  ```dart
  SizedBox(height: 12),
  _CalibrationDataCard(),
  ```
  Preserve the existing `const` usage on the surrounding `Column` / `SingleChildScrollView` — if adding a non-const widget breaks `const Column(...)`, drop the `const` from the `Column` (and `children:` list) as needed so the file still compiles. Keep the spacing pattern (`SizedBox(height: 12)`) consistent with how `_NfbCard` follows `_CalibrationCard`.
