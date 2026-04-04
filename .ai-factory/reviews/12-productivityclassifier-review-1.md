## Code Review Summary

**Plan:** `12-productivityclassifier.md`
**Files Changed:** 3 (channel_names.dart, productivity_classifier.dart [new], neiry_kit.dart)
**Risk Level:** 🟢 Low

### Critical Issues

None.

### Minor Issues

None.

### Verification

**channel_names.dart** — Two new constants added (`productivityBaselines`, `productivityIndividualNfb`). Grouped correctly with existing productivity events, before the cardio section. String values follow the `neiry_kit/events/<camelCase>` convention. ✓

**productivity_classifier.dart** — New file, 297 lines. Verified against NfbClassifier, PhysioClassifier, and EmotionsClassifier:

- **Imports:** `dart:async`, `package:flutter/services.dart` (re-exports `Uint8List` from `dart:typed_data` — no separate import needed, consistent with PhysioClassifier). Five model imports with correct relative paths for the `classifiers/` subdirectory depth. ✓
- **Two factory constructors:** Both guard on `device.isStarted`, throw `StateError` with descriptive message, delegate to the private constructor. `.withCalibration` passes `IndividualNfbData` through. ✓
- **Private constructor:** Branches on `calibration != null` — uses `ClassifierMethods.createCalibrated` / `ClassifierMethods.create` respectively. Both constants verified present in `channel_names.dart` (lines 109, 108). `catchError` pattern captures into `_createError`, identical to NfbClassifier. ✓
- **Static channel:** `MethodChannel(NeiryChannels.productivity)` — constant verified at `channel_names.dart:16`. ✓
- **Seven cached streams:** All use `late final` + `_eventStream` helper with `const EventChannel(...)`:
  - `_baselineStream` → `NeiryEvents.productivityBaselines` + `ProductivityBaselines.fromMap(Map<Object?, Object?>)` ✓
  - `_indexesStream` → `NeiryEvents.productivityIndexes` + `ProductivityIndexes.fromMap(Map<Object?, Object?>)` ✓
  - `_metricsStream` → `NeiryEvents.productivityMetrics` + `ProductivityMetrics.fromMap(Map<Object?, Object?>)` ✓
  - `_calibrationProgress` → `NeiryEvents.productivityCalibrationProgress` + `(map['progress'] as num).toDouble()` — matches PhysioClassifier exactly ✓
  - `_calibrated` → `NeiryEvents.productivityCalibrated` + `map['baselines'] as Uint8List` — matches PhysioClassifier exactly ✓
  - `_individualNfbStream` → `NeiryEvents.productivityIndividualNfb` + `NfbUserState.fromMap(Map<Object?, Object?>)` ✓
  - `_errorStream` → `NeiryEvents.productivityError` + `map['message'] as String` — matches NfbClassifier and EmotionsClassifier error stream pattern ✓
- **All model `fromMap` signatures** accept `Map<Object?, Object?>`, matching the `_eventStream` helper's decode function type. Verified in source. ✓
- **`IndividualNfbData.toMap()`** returns `Map<String, dynamic>`, compatible with MethodChannel argument passing. ✓
- **Seven public stream getters:** All guarded with `_checkNotDisposed()` → `_checkReady()`, return types match cached fields. ✓
- **Three methods** (`startBaselineCalibration`, `importBaselines`, `resetAccumulatedFatigue`): All follow the PhysioClassifier pattern — `_checkNotDisposed()` → `await _nativeReady` → `_checkReady()` → `invokeMethod`. Method name constants and argument keys all verified present in `channel_names.dart`. ✓
- **Guards:** `_checkNotDisposed()` and `_checkReady()` — identical to PhysioClassifier with correct `'ProductivityClassifier'` in error messages. ✓
- **`_eventStream` helper:** Identical to all other classifiers — `receiveBroadcastStream({NeiryArgs.serial: _serial}).map(...)`. ✓
- **`dispose()`:** Idempotent, sets `_disposed = true` before awaiting, early-returns on `_createError != null`, invokes `ClassifierMethods.dispose`. Matches PhysioClassifier/NfbClassifier/EmotionsClassifier. ✓

**neiry_kit.dart** — Export added at line 4, after `physio_classifier.dart` (line 3). Alphabetically correct (`ph` < `pr`). ✓

### Notes

- The `ClassifierMethods.stopBaselineCalibration` constant exists but is not exposed — consistent with PhysioClassifier which also omits it.
- No runtime-breaking issues found: all constants exist, all model factory signatures match, all patterns are identical to the proven sibling classifiers.

REVIEW_PASS
