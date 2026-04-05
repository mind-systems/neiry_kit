# Explore: NfbCalibrator Lifecycle & Stage Mapping

Research findings from C header inspection before implementing `NfbBridge + NfbCalibratorBridge` iOS milestone.

## Two separate bridge classes

`NfbBridge` and `NfbCalibratorBridge` are **separate Swift classes** with separate C handles and separate channels:

| Class | C handle | MethodChannel | EventChannel |
|---|---|---|---|
| `NfbBridge` | `clCNFB` | `neiry_kit/device` (shared, dispatch on method name) | `neiry_kit/events/nfbState` |
| `NfbCalibratorBridge` | `clCNFBCalibrator` | `neiry_kit/nfb_calibrator` | `neiry_kit/events/nfbCalibration` |

Neither bridge holds the other. They communicate only through the device handle.

## Calibrator creation

```c
clCNFBCalibrator clCNFBCalibrator_CreateOrGet(clCDevice device);
```

No error parameter. Returns a cached handle per device — the same pointer is returned on repeated calls for the same device. Do NOT call any destroy function on it.

## NFB classifier creation

```c
clCNFB clCNFB_Create(clCDevice device, clCError* error);
clCNFB clCNFB_CreateCalibrated(clCDevice device, clCNFBCalibrator calibrator, clCError* error);
```

The calibrated path takes the **calibrator handle**, not the data struct. Get the calibrator via `clCNFBCalibrator_CreateOrGet(device)`.

## Stage callbacks — SDK does NOT pass stage number

```c
typedef void (*clCNFBCalibrator_CalibrationStageFinishedHandler)(clCNFBCalibrator calibrator) NOEXCEPT;
void clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(clCNFBCalibrator, handler);

typedef void (*clCNFBCalibrator_CalibratedHandler)(clCNFBCalibrator, const clCIndividualNFBData*) NOEXCEPT;
void clCNFBCalibrator_SetOnCalibratedEvent(clCNFBCalibrator, handler);
```

The stage-finished callback receives **only the calibrator handle** — no stage number. The bridge must track `currentStage: Int` internally and increment it on each `StageFinished` callback.

Stage enum values (0-indexed in C):
- `clCIndividualNFBCalibrationStage_1` = 0 — closed eyes, 20s
- `clCIndividualNFBCalibrationStage_2` = 1 — open eyes, 20s
- `clCIndividualNFBCalibrationStage_3` = 2 — closed eyes, 20s
- `clCIndividualNFBCalibrationStage_4` = 3 — open eyes, 20s

## Full calibration flow

```
Dart calls calibrateIndividual() on MethodChannel
  → NfbCalibratorBridge sets currentStage = 0
  → calls clCNFBCalibrator_CalibrateIndividualNFB(calibrator, stage_1, &error)
  → onStageFinished fires → emit {'type':'stage','stage':1}, currentStage = 1
  → calls clCNFBCalibrator_CalibrateIndividualNFB(calibrator, stage_2, &error)
  → onStageFinished fires → emit {'type':'stage','stage':2}, currentStage = 2
  → (repeat for stages 3 and 4)
  → onCalibrated fires → emit {'type':'done', ...IndividualNfbData fields}
```

The bridge is responsible for advancing stages. The SDK does not auto-advance.

## Quick calibration — MethodChannel, not EventChannel

```c
void clCNFBCalibrator_CalibrateIndividualNFBQuick(clCNFBCalibrator, clCError*);
```

Quick mode uses the **same** `SetOnCalibratedEvent` callback but returns a single result, not a stream. The native bridge must hold the MethodChannel `result` sink and call it from the `onCalibrated` callback. Do NOT emit on the EventChannel for quick mode.

- `calibrateIndividual()` → EventChannel stream
- `calibrateIndividualQuick()` → MethodChannel Future (single result via `result.success(...)`)

## Other calibrator functions

```c
// Import/export
void clCNFBCalibrator_ImportIndividualNFBData(clCNFBCalibrator, const clCIndividualNFBData*, clCError*);
void clCNFBCalibrator_GetIndividualNFB(clCNFBCalibrator, clCIndividualNFBData* out, clCError*);

// State checks — no error param
bool clCNFBCalibrator_IsCalibrated(clCNFBCalibrator);
bool clCNFBCalibrator_HasCalibrationFailed(clCNFBCalibrator);
```

`IsCalibrated` and `HasCalibrationFailed` return bool directly with no error parameter — do NOT wrap in `do/catch checkCError`.

`ImportIndividualNFBData` takes `const clCIndividualNFBData*` — the bridge must deserialize the Dart map back to the C struct before calling.

## IndividualNfbData map shape (EventChannel `done` event and MethodChannel quick result)

```
{
  'ts':                              Int64  (timestampMilli, default -1)
  'failReason':                      Int    (0=None, 1=TooManyArtifacts, 2=PeakIsABorder)
  'individualFrequency':             Double (Hz, default 10.0)
  'individualPeakFrequency':         Double (Hz, default 10.0)
  'individualPeakFrequencyPower':    Double (μV²/Hz, default 10.0)
  'individualPeakFrequencySuppression': Double (closed/open ratio, default 2.0)
  'individualBandwidth':             Double (Hz, default 6.0)
  'individualNormalizedPower':       Double (0–1, default 0.5)
  'lowerFrequency':                  Double (Hz, default 7.0)
  'upperFrequency':                  Double (Hz, default 13.0)
}
```

These field names must match `IndividualNfbData.fromMap` on the Dart side exactly.

## Resolved

1. **No `Cancel()` function.** `CNFBCalibrator.h` full listing confirmed: only `CalibrateIndividualNFB`, `CalibrateIndividualNFBQuick`, `ImportIndividualNFBData`, `GetIndividualNFB`, `IsCalibrated`, `HasCalibrationFailed`, and two event setters. No cancel. To abort, call `clCNFBCalibrator_CalibrateIndividualNFB` with the next stage (which interrupts the current one) or disconnect the device. Dart-side `NfbCalibrator.stopCalibration()` calls `NFBCalibratorMethods.stopCalibration` MethodChannel — bridge must handle this by simply stopping further stage advancement (no C call available).
2. **Overlap guard already implemented.** `NfbCalibrator.calibrateIndividual()` calls `_cancelActiveCalibration()` + a fire-and-forget native `stopCalibration` before starting — cancel-on-overlap is in `nfb_calibrator.dart:96–99`.
3. **`CreateOrGet` across stop/start cycles:** Not documented in headers. Bridge should cache the handle between start/stop cycles and call `CreateOrGet` again after each `start()` — if SDK returns the same pointer, no harm; if it returns a new one, the cached value is refreshed. Add a comment in the bridge noting this uncertainty.
