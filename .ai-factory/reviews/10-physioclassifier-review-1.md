# Code Review: PhysioClassifier

**Plan:** `.ai-factory/plans/10-physioclassifier.md`
**Changed files:** `lib/src/api/classifiers/physio_classifier.dart` (new), `lib/src/channel/channel_names.dart` (modified), `lib/neiry_kit.dart` (modified)
**Verification:** `flutter analyze lib/` — 0 issues; `flutter test` — 118/118 pass

## Reviewed

### `lib/src/channel/channel_names.dart`

- New `physiologicalIndividualNfb` EventChannel ID placed correctly after `physiologicalCalibrated`, keeping the physio group contiguous.
- Value string follows naming convention. No duplicates (confirmed by existing uniqueness test — count bumped to 26 and test passes).

### `lib/src/api/classifiers/physio_classifier.dart`

**Structure matches NfbClassifier exactly** — same `_nativeReady`/`_createError` lifecycle, same `_eventStream` helper, same `_checkNotDisposed()`/`_checkReady()` guard pair, same idempotent `dispose()`. Correct differences from NfbClassifier:

- No `calibration` constructor parameter (correct — physio uses `startBaselineCalibration`/`importBaselines` instead of constructor-time calibration).
- Two async methods (`startBaselineCalibration`, `importBaselines`) with proper guard ordering: sync `_checkNotDisposed()` → `await _nativeReady` → sync `_checkReady()` → native call.
- Four streams instead of two, all using correct EventChannel IDs and decode functions.

**Stream decode functions verified against models:**
- `stateStream` → `PhysiologicalStatesValue.fromMap` — signature matches (`Map<Object?, Object?> → PhysiologicalStatesValue`). ✅
- `calibrationProgress` → `(map['progress'] as num).toDouble()` — uses `num` cast which handles both `int` and `double` from `StandardMessageCodec`. ✅
- `calibrated` → `map['baselines'] as Uint8List` — `Uint8List` is natively supported by `StandardMessageCodec`, no serialization issues. ✅
- `individualNfbStream` → `NfbUserState.fromMap` — signature matches. ✅

**`Uint8List` availability:** Not explicitly imported from `dart:typed_data`, but `package:flutter/services.dart` re-exports it. Static analysis confirms this resolves correctly.

**Channel/method constants verified:**
- `NeiryChannels.physiological` → `'neiry_kit/physiological'` ✅
- `ClassifierMethods.create`, `.startBaselineCalibration`, `.importBaselines`, `.dispose` — all exist in `ClassifierMethods` ✅
- `NeiryArgs.serial`, `.baselines` — both exist in `NeiryArgs` ✅
- All four EventChannel IDs exist in `NeiryEvents` ✅

### `lib/neiry_kit.dart`

- Export added after `nfb_classifier.dart`, keeping classifier exports grouped. ✅
- File path `src/api/classifiers/physio_classifier.dart` matches actual file location. ✅

## Critical Issues

None.

## Minor Notes

- The `calibrationProgress` and `calibrated` streams establish map key names (`'progress'`, `'baselines'`) that native bridges must honor. These keys are not yet codified in `NeiryArgs` (unlike `serial` or `baselines` as an argument key). This is consistent with how NfbClassifier's `errorStream` uses inline `'message'` key. Not a bug — just a contract the native bridge milestones will need to match.

REVIEW_PASS
