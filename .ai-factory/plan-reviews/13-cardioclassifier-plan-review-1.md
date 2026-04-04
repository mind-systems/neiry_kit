# Plan Review: CardioClassifier

**Plan:** `.ai-factory/plans/13-cardioclassifier.md`
**Files Reviewed:** 5 tasks across 5 files
**Risk Level:** :yellow_circle: Medium

## Context Gates

- **ARCHITECTURE.md:** `WARN` — Plan aligns with the layered plugin architecture (models → channel → api → barrel). Dependency rules respected. No boundary violations.
- **RULES.md:** File not present. `WARN` — no explicit convention violations detected; plan follows established codebase patterns.
- **ROADMAP.md:** `WARN` — Plan implements the `CardioClassifier` milestone (Dart API section). Roadmap entry matches the plan scope.

## Critical Issues

### 1. `errorStream` has no C API backing

**Task 3 + Task 4** — The plan adds a `cardioError` EventChannel constant and wires an `errorStream` in `CardioClassifier`. However, the C header `CCardio.h` exposes only three callbacks:

- `clCCardio_SetOnIndexesUpdateEvent` (data)
- `clCCardio_SetOnCalibratedEvent` (calibration complete)
- `clCCardio_SetOnPPGDataEvent` (raw PPG)

There is **no** `clCCardio_SetOnErrorEvent`. The C++ `ClassificationCardio` class also has no error callback, and the base `Classification` class doesn't define one either.

Other classifiers that expose `errorStream` (NFB, Emotions, Productivity) each have a matching `SetOnErrorEvent` in their C headers. Cardio does not.

**Impact:** The native bridge will have nothing to wire to this EventChannel. The stream will never emit. Shipping a dead `errorStream` in the public API is misleading — consumers will assume errors are reported there and miss that Cardio errors only surface through synchronous `clCError*` out-parameters (caught as `PlatformException` on the Dart side).

**Fix:** Remove Task 3 entirely (do not add `cardioError` constant). Remove `errorStream` from Task 4. If a future SDK version adds an error callback, the constant and stream can be added then.

### 2. Missing `calibratedStream` — C API callback exists but plan doesn't expose it

The C API defines `clCCardio_SetOnCalibratedEvent`, and the `NeiryEvents.cardioCalibratedEvent` constant already exists in `channel_names.dart`. This callback fires when the Cardio classifier's internal calibration completes (after `CreateCalibrated`).

The plan's `CardioClassifier` exposes only `stateStream` and `ppgStream` (and the problematic `errorStream`) — no stream for the calibrated event.

The callback signature `void (*)(clCCardio)` carries no data payload, but consumers still need to know when calibration finishes. Without this, there's no way to distinguish "still calibrating" from "calibrated and producing valid metrics".

**Fix:** Add a `Stream<void>` (or `Stream<bool>`) `calibratedStream` that emits once when the native side fires `clCCardio_SetOnCalibratedEvent`. Wire it to the existing `NeiryEvents.cardioCalibratedEvent` EventChannel. Decode as `(map) => null` (or `(map) => true`).

### 3. Sentinel convention mismatch for float fields

The plan says `heartRate`, `stressIndex`, and `kaplanIndex` should use `orNull` from `sentinel.dart` (negative → `null`). But the C struct `clCCardio_Data` initializes these to `0.F`, not `-1.F`:

```c
float heartRate = 0.F;
float stressIndex = 0.F;
float kaplanIndex = 0.F;
```

Every other classifier struct in the codebase uses `-1.F` as the sentinel (matching `CLAUDE.md`: "All structs use `-1.F` / `-1` as sentinel for not yet available"). Cardio is the exception — `0.F` default means `orNull` will never trigger for these fields; a 0.0 heartRate will pass through as a seemingly valid `double` instead of `null`.

The `metricsAvailable` boolean flag is the real validity indicator, and the plan correctly makes it required. But the `orNull` wrapping creates a false sense of safety — consumers may think `heartRate != null` means the value is valid, when it could be the `0.0` default.

**Fix:** Either:
- (a) Keep `orNull` but document explicitly that `metricsAvailable` must be checked — the `null` conversion is best-effort and may not trigger for Cardio floats. Add a doc comment on each nullable field.
- (b) Make the float fields non-nullable (`double`, required) and document that values are only meaningful when `metricsAvailable == true`. This is arguably more honest given the C struct defaults.

Option (b) matches the C struct more faithfully. Option (a) is consistent with other classifiers but slightly misleading.

## Suggestions

### 4. Spec notes reference wrong C callback name

The spec notes (`04-dart-api-classifiers.md`) reference `clCCardio_SetOnCardioDataUpdatedEvent`, but the actual C API function is `clCCardio_SetOnIndexesUpdateEvent`. This doesn't affect the Dart plan (the Dart side doesn't call C functions), but will mislead whoever implements the native bridges. Consider correcting the spec notes.

### 5. `PpgData.timestamps` should use `List<int>` consistently

Task 2 specifies `timestamps` as `List<int>` decoded via `(v as num).toInt()`. The C API returns `uint64_t` timestamps from `clCPPGTimedData_GetTimestampMilli`. On 64-bit platforms Dart `int` is 64 bits so this is fine, but the decode should use `toInt()` not `toDouble()` — which the plan already does correctly. No action needed, just confirming correctness.

### 6. Consider exposing `CardioMetrics` in the future

The C++ `ClassificationCardio` class has a `SetOnMetricsUpdateEvent` callback with a separate `cardio::CardioMetrics` type. This has no C API counterpart in the current SDK, so it's correctly excluded. However, if the C API evolves to expose it, a fourth stream will be needed. Worth noting in a doc comment.

## Positive Notes

- The plan correctly follows the established `ProductivityClassifier` pattern for two-factory constructor paths, async native creation, cached streams, guard methods, and idempotent dispose.
- `PpgData` model design (flat lists + count) correctly mirrors the `clCPPGTimedData` accessor pattern from the C header.
- Barrel export ordering is correct — all three new exports are alphabetically placed.
- The plan correctly identifies that `cardioData` and `ppgData` EventChannel constants already exist, and only the missing `cardioError` needs adding (though per issue #1, it shouldn't be added either).
- Import paths in Task 4 are all verified correct relative to `lib/src/api/classifiers/`.
