# Code Review: CardioClassifier

**Plan:** `.ai-factory/plans/13-cardioclassifier.md`
**Files reviewed:** `lib/src/models/cardio_data.dart`, `lib/src/models/ppg_data.dart`, `lib/src/api/classifiers/cardio_classifier.dart`, `lib/neiry_kit.dart`

## Plan compliance

All four tasks implemented correctly. All three critical issues from the plan review are resolved:

1. **No `errorStream`** — Correctly omitted. No `cardioError` EventChannel constant added. The class doc comment explains that errors surface as `PlatformException`. ✓
2. **`calibratedStream` added** — Wired to `NeiryEvents.cardioCalibratedEvent` as `Stream<void>`, bypasses `_eventStream` helper since the callback carries no data payload. ✓
3. **Non-nullable float fields** — `heartRate`, `stressIndex`, `kaplanIndex` are `double` (required), not `double?` via `orNull`. Each field has a doc comment stating the value is only meaningful when `metricsAvailable` is `true`. ✓

## Critical Issues

None.

## Minor observations (non-blocking)

### 1. `@immutable` on classes with mutable `List` fields

`PpgData` is annotated `@immutable` but holds `List<double>` and `List<int>` — mutable types. A consumer could do `ppg.values.add(42.0)` and mutate shared state. This is not a bug introduced by this PR — `EegData` in the same codebase has the identical pattern (`List<List<double>>` fields with `@immutable`). Consistent with existing convention; no action needed.

### 2. `dart:async` import

`CardioClassifier` imports `dart:async`. In modern Dart, `Future` and `Stream` are available via `dart:core`. However, `ProductivityClassifier` and all other classifiers also import `dart:async`, so this is consistent. No action needed.

## Verification checklist

- [x] **CardioData model** — `@immutable`, `const` constructor, named required params, `fromMap` factory. Float fields decoded as `(map[key] as num).toDouble()`. Bool fields cast directly. `timestamp` decoded via `DateTime.fromMillisecondsSinceEpoch`. Matches `NfbUserState` structure minus `orNull` (correctly, per plan review issue #3).
- [x] **PpgData model** — `@immutable`, `const` constructor, `fromMap` factory. List decoding matches `EegData` pattern: `(v as num).toDouble()` for values, `(v as num).toInt()` for timestamps.
- [x] **CardioClassifier** — Two factories with `device.isStarted` guard, private `._` constructor with async native creation via `_channel.invokeMethod`, `catchError` into `_createError`. Three cached `late final` streams (`_stateStream`, `_ppgStream`, `_calibratedStream`). Guards (`_checkNotDisposed`, `_checkReady`), `_eventStream<T>` helper, idempotent `dispose()`. All match `ProductivityClassifier` exactly.
- [x] **`_calibratedStream`** — Correctly bypasses `_eventStream` helper (no `Map` cast needed for void-payload event). Uses `receiveBroadcastStream({NeiryArgs.serial: _serial}).map((_) {})`.
- [x] **Channel constants** — Uses existing `NeiryChannels.cardio`, `NeiryEvents.cardioData`, `NeiryEvents.ppgData`, `NeiryEvents.cardioCalibratedEvent`. No new constants added (correct — `cardioError` intentionally omitted).
- [x] **Barrel exports** — Three exports added in correct alphabetical positions: `cardio_classifier` before `emotions_classifier`; `cardio_data` between `calibration_stage` and `device_info`; `ppg_data` between `physio_states` and `productivity_baselines`.
- [x] **Import paths** — All relative imports in `cardio_classifier.dart` verified correct: `../device.dart`, `../../channel/channel_names.dart`, `../../models/cardio_data.dart`, `../../models/ppg_data.dart`, `../../models/individual_nfb_data.dart`.
- [x] **No sentinel misuse** — `CardioData` does not import `sentinel.dart`. Float fields are non-nullable `double`, matching the C struct's `0.F` initialization.

REVIEW_PASS
