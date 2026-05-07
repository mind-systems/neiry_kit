# Code Review: MEMSClassifier Dart API

**Plan:** `45-memsclassifier-dart-api.md`
**Files changed:** 3 (`mems_classifier.dart` new, `channel_names.dart` modified, `neiry_kit.dart` modified)
**Static analysis:** `flutter analyze lib/` — 0 issues

## Verification

- `IndividualNfbData.toMap()` exists (line 90 of `individual_nfb_data.dart`) — confirmed.
- `MemsSample.fromMap(Map<Object?, Object?>)` exists — confirmed.
- `NeiryEvents.memsData` already existed (line 42) — no duplicate introduced.
- `NeiryChannels.mems` added on line 18 — correct placement between `cardio` and `nfbCalibrator`.
- Barrel export placed alphabetically between `emotions_classifier.dart` and `nfb_classifier.dart` — correct.
- `Device.isStarted` (line 287) and `Device.serial` (line 39) — both accessible.
- `late final` stream field captures `_serial` safely (field is `final`, assigned before any access).
- `catchError` callback type matches `Future<void>` — no return needed.

## Pattern conformance

The implementation follows `CardioClassifier` line-for-line:
- Factory constructors with `isStarted` guard
- Private constructor fires async `invokeMethod` with `catchError`
- `_nativeReady` / `_createError` pattern
- `_checkNotDisposed()` / `_checkReady()` guards
- Idempotent `dispose()` awaiting `_nativeReady`

Only intentional deviation: `_memsStream` inlines the mapping (casts raw to `List`, maps each element) instead of using an `_eventStream` helper — correct, since the data shape is `List<MemsSample>` (batched) rather than a single map.

## Findings

None. The implementation is correct, type-safe, and consistent with existing classifiers.

REVIEW_PASS
