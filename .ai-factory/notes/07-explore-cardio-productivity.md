# Explore: Cardio & Productivity Bridge Pitfalls

Research findings from C header inspection before implementing `ProductivityBridge` and `CardioBridge` iOS milestones.

## Classifier lifecycle — NO destroy function

Classifiers (Cardio, NFB, Emotions, Productivity, PhysiologicalStates) have **no `*_Destroy()` function** in the C API. Lifecycle is managed by the SDK internally. Do NOT call a destroy; cleanup happens automatically when the parent device is released.

Compare:
- `clCDeviceLocator_Destroy(locator)` — exists ✅
- `clCDevice_Release(device)` — exists ✅
- `clCCardio_Destroy(cardio)` — **does NOT exist** ❌

## Cardio — creation

Two factory functions:

```c
clCCardio clCCardio_Create(clCDevice device, clCError* error);
clCCardio clCCardio_CreateCalibrated(clCDevice device, clCNFBCalibrator calibrator, clCError* error);
```

The `withCalibration` path takes a **`clCNFBCalibrator` handle** (opaque), not an `IndividualNfbData` struct. The calibrator is obtained via `clCNFBCalibrator_CreateOrGet(device)`.

Device must already be started (`clCDevice_Start`) before creating a classifier.

## Productivity — creation

Two factory functions:

```c
clCProductivity clCProductivity_Create(clCDevice device, clCError* error);
clCProductivity clCProductivity_CreateWithIndividualData(clCDevice device, const clCIndividualNFBData* data, clCError* error);
```

Unlike Cardio, the `withCalibration` path takes a **pointer to the data struct**, not a calibrator handle. The bridge must convert the Dart-side `IndividualNfbData` map back to `clCIndividualNFBData` and pass it by pointer. The SDK copies the data internally — no ownership transfer.

## CardioData — direct struct, no accessor functions

CardioData is delivered in callbacks as `const clCCardio_Data*`. Fields are accessed directly from the struct — there are no getter functions (unlike PSD data).

```c
typedef struct clCCardio_Data {
    int64_t timestampMilli;  // -1 = no data
    float heartRate;
    float stressIndex;
    float kaplanIndex;
    bool hasArtifacts;       // ⚠️ initialized to 0.F in header (float literal, not false)
    bool skinContact;        // ⚠️ same
    bool motionArtifacts;    // ⚠️ same
    bool metricsAvailable;   // ⚠️ same
} clCCardio_Data;
```

**Bool fields initialized to `0.F` (float literal) — header bug.** This compiles on ARM64 but is technically UB. Read the bool values normally from the struct; do not assume they are unreliable.

Callback registration:
```c
typedef void (*clCCardio_IndexesUpdateHandler)(clCCardio, const clCCardio_Data*) NOEXCEPT;
void clCCardio_SetOnIndexesUpdateEvent(clCCardio cardio, clCCardio_IndexesUpdateHandler handler, clCError* error);
```

## CardioData — PPG uses accessor pattern (different from CardioData)

PPG data uses accessor functions, unlike the direct-struct CardioData:
```c
int32_t clCPPGTimedData_GetCount(clCPPGTimedData ppgTimedData);
float   clCPPGTimedData_GetValue(clCPPGTimedData ppgTimedData, int32_t index);
uint64_t clCPPGTimedData_GetTimestampMilli(clCPPGTimedData ppgTimedData, int32_t index);
```

## Cardio — calibrated callback

When using `CreateCalibrated`, register an additional callback:
```c
typedef void (*clCCardio_CalibratedHandler)(clCCardio) NOEXCEPT;
void clCCardio_SetOnCalibratedEvent(clCCardio cardio, clCCardio_CalibratedHandler handler, clCError* error);
```

## Productivity — callback registrations take NO clCError*

All four `SetOn*Event` functions for Productivity take no error parameter. Registration is fire-and-forget:

| Function | Error param |
|---|---|
| `clCProductivity_Create` | ✅ `clCError*` |
| `clCProductivity_CreateWithIndividualData` | ✅ `clCError*` |
| `clCProductivity_ImportBaselines` | ✅ `clCError*` |
| `clCProductivity_ResetAccumulatedFatigue` | ✅ `clCError*` |
| `clCProductivity_StartBaselineCalibration` | ❌ none |
| `clCProductivity_SetOnMetricsUpdateEvent` | ❌ none |
| `clCProductivity_SetOnIndexesUpdateEvent` | ❌ none |
| `clCProductivity_SetOnBaselineUpdateEvent` | ❌ none |
| `clCProductivity_SetOnCalibrationProgressUpdateEvent` | ❌ none |
| `clCProductivity_SetOnIndividualNFBUpdateEvent` | ❌ none |

Same exception pattern as DeviceBridge's `clCDevice_Start` — no error return for `StartBaselineCalibration`.

## Productivity — three distinct data structs

| Callback | Struct | Frequency |
|---|---|---|
| `SetOnMetricsUpdateEvent` | `clCProductivity_Metrics` | Continuous, high-frequency |
| `SetOnIndexesUpdateEvent` | `clCProductivity_Indexes` | Continuous, lower frequency |
| `SetOnBaselineUpdateEvent` | `clCProductivity_Baselines` | Once per calibration + on import |

**`clCProductivity_Metrics` has `artifactsData` / `artifactsSize` fields** — opaque blob, map to `Uint8List` on Dart side.

`clCProductivity_Indexes` has `relaxation` (`clCProductivity_RecommendationValue` enum 0–5) and `stress` (`clCProductivity_StressValue` enum 0–2).

## resetAccumulatedFatigue — streaming safety not guaranteed

```c
void clCProductivity_ResetAccumulatedFatigue(clCProductivity productivity, clCError* error);
```

Safe to call during streaming in practice, but the SDK does not document atomicity guarantees. Metrics values may briefly show stale fatigue during the reset window. Add a comment in the bridge.
