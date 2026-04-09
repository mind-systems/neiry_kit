# Plan Review: CardioBridge

**Plan file:** `.ai-factory/plans/26-cardiobridge.md`
**Files reviewed:** 12 (plan, C headers, existing bridges, plugin dispatcher, Dart API & models, channel constants, exploration notes)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the established "one bridge class per C API module" principle, uses `DeviceStreamHandler` for event dispatch, and integrates into `NeiryKitPlugin.swift` via the same lookup-dictionary pattern as all other bridges.
- **RULES.md:** File not present. `WARN` — non-blocking.
- **ROADMAP.md:** PASS — the CardioBridge milestone is listed as unchecked (`[ ]`) under "iOS bridges". The plan scope matches the roadmap description exactly. One note: the roadmap line mentions `cardioError` as an EventChannel, but neither the C API (`CCardio.h`) nor the Dart API (`CardioClassifier`) expose an error callback — the plan correctly omits it. The roadmap description is slightly stale here.

## Critical Issues

None.

## Suggestions

### 1. `registerCallbacks()` intro says "Both" — should say "All three"

**File:** plan Task 1, `registerCallbacks()` section header

The plan states:

> Both `SetOnIndexesUpdateEvent` and `SetOnCalibratedEvent` take `clCError*`

The C header (`CCardio.h` lines 31, 34, 37) shows that **all three** registration functions take `clCError*`:

```c
void clCCardio_SetOnIndexesUpdateEvent(clCCardio, clCCardio_IndexesUpdateHandler, clCError*);
void clCCardio_SetOnCalibratedEvent(clCCardio, clCCardio_CalibratedHandler, clCError*);
void clCCardio_SetOnPPGDataEvent(clCCardio, clCCardio_PPGDataHandler, clCError*);
```

Additionally, the individual callback descriptions for items 1 and 3 mention error handling, but item 2 (PPG callback) does not explicitly describe the `var e = clCError()` + `try checkCError(e)` wrapping. An implementer following the plan item-by-item could register the PPG callback without error checking.

**Fix:** Change "Both `SetOnIndexesUpdateEvent` and `SetOnCalibratedEvent`" to "All three callbacks (`SetOnIndexesUpdateEvent`, `SetOnPPGDataEvent`, and `SetOnCalibratedEvent`)". Add explicit `clCError*` mention to item 2 (PPG), matching the style of item 3.

## Positive Notes

- **Thorough pattern references.** The plan explicitly names which existing bridge to follow for each aspect (NfbBridge for two-factory paths, PhysioBridge for throwing `registerCallbacks`) — this eliminates guesswork.
- **Map key alignment verified.** The bridge-side map keys (`ts`, `heartRate`, `stressIndex`, `kaplanIndex`, `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable`) match `CardioData.fromMap` exactly. PPG keys (`values`, `timestamps`, `sampleCount`) match `PpgData.fromMap` exactly.
- **C API signatures verified.** All function names, callback typedefs, and struct field names in the plan match `CCardio.h` and `CPPGTimedData.h` headers exactly.
- **Event channel IDs verified.** All three channel IDs in the plan match both `NeiryEvents` Dart constants and the `NeiryKitPlugin.swift` registration list.
- **Plugin integration is complete.** The plan covers all six touch points in `NeiryKitPlugin.swift`: property declaration, instantiation, method dispatch branch, handler method, event channel lookup, and dispose chain. Nothing is missing.
- **Correctly omits error event.** The Cardio C API has no `SetOnErrorEvent` — the plan correctly defines only 3 stream handlers, matching the Dart API which documents this explicitly.
