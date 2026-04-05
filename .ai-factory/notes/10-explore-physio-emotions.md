# Explore: PhysioBridge & EmotionsBridge Pitfalls

Research findings from C header inspection before implementing `PhysioBridge + EmotionsBridge` iOS milestone.

## Two separate bridge classes

`PhysioBridge` and `EmotionsBridge` are separate Swift classes with separate C handles and separate channels.

| Class | C handle | MethodChannel | EventChannels |
|---|---|---|---|
| `PhysioBridge` | `clCPhysiologicalStates` | `neiry_kit/physio` | `nfbState`, `nfbCalibrationProgress`, `nfbCalibrated`, `nfbIndividualNfb` |
| `EmotionsBridge` | `clCEmotions` | `neiry_kit/emotions` | `neiry_kit/events/emotionsState` |

## No Destroy functions

Neither `clCPhysiologicalStates` nor `clCEmotions` has a `_Destroy()` or `_Release()` function — lifecycle is SDK-managed, same as Cardio/NFB/Productivity. Do NOT call destroy; cleanup happens automatically when the parent device is released.

## Error parameter asymmetry — critical difference

This is the most important thing to get right:

| Classifier | SetOn*Event takes clCError*? |
|---|---|
| PhysiologicalStates | **YES** — all 4 SetOn*Event functions take `clCError*` |
| Emotions | **NO** — both SetOn*Event functions take NO `clCError*` |

This asymmetry mirrors the Cardio (YES) vs Productivity (NO) pattern found in `07-explore-cardio-productivity.md`.

**Rule:** Wrap all `clCPhysiologicalStates_SetOn*Event` calls in `do/catch checkCError`. Do NOT wrap `clCEmotions_SetOn*Event` calls.

## PhysiologicalStates — full function table

| Function | Error param | Notes |
|---|---|---|
| `clCPhysiologicalStates_Create(device, &error)` | YES | |
| `clCPhysiologicalStates_ImportBaselines(states, baselines)` | **NO** | Takes `const clCPhysiologicalStates_Baselines*` |
| `clCPhysiologicalStates_StartBaselineCalibration(states)` | **NO** | Same pattern as Productivity |
| `clCPhysiologicalStates_SetOnStatesUpdateEvent(states, handler, &error)` | YES | |
| `clCPhysiologicalStates_SetOnCalibratedEvent(states, handler, &error)` | YES | |
| `clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(states, handler, &error)` | YES | |
| `clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(states, handler, &error)` | YES | |

## Emotions — full function table

| Function | Error param | Notes |
|---|---|---|
| `clCEmotions_Create(device, &error)` | YES | |
| `clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, handler)` | **NO** | |
| `clCEmotions_SetOnErrorEvent(emotions, handler)` | **NO** | |

## Baselines are a struct, NOT opaque bytes

**Critical finding:** `clCPhysiologicalStates_Baselines` is a well-defined C struct, not an opaque blob.

```c
typedef struct clCPhysiologicalStates_Baselines {
    int64_t timestampMilli;   // -1 = unavailable
    float alpha;              // -1.F = unavailable
    float beta;               // -1.F = unavailable
    float alphaGravity;       // -1.F = unavailable
    float betaGravity;        // -1.F = unavailable
    float concentration;      // -1.F = unavailable
} clCPhysiologicalStates_Baselines;
```

**Import:** `clCPhysiologicalStates_ImportBaselines(states, const clCPhysiologicalStates_Baselines*)` — NO error param. The bridge must deserialize the Dart map back to this struct before calling. The SDK copies internally.

**Export:** Returned via `CalibratedHandler` callback as `const clCPhysiologicalStates_Baselines*`. The bridge must serialize all 6 fields to a Dart map.

Contrast with `clCProductivity_ImportBaselines` which DOES take `clCError*` — inconsistency in the SDK.

## PhysiologicalStates_Value struct

```c
typedef struct clCPhysiologicalStates_Value {
    int64_t timestampMilli;   // -1 = unavailable
    float relaxation;         // [0,1] or -1.F
    float fatigue;            // [0,1] or -1.F
    float none;               // [0,1] or -1.F
    float concentration;      // [0,1] or -1.F
    float involvement;        // [0,1] or -1.F
    float stress;             // [0,1] or -1.F
    bool nfbArtifacts;
    bool cardioArtifacts;
} clCPhysiologicalStates_Value;
```

Two extra fields vs Dart model: `nfbArtifacts` + `cardioArtifacts` (bool). Include both in the emitted map.

## Emotions_States struct

```c
typedef struct clCEmotions_States {
    int64_t timestampMilli;
    float attention;          // [0,1] or -1.F
    float relaxation;         // [0,1] or -1.F
    float cognitiveLoad;      // [0,1] or -1.F
    float cognitiveControl;   // [0,1] or -1.F
    float selfControl;        // [0,1] or -1.F
} clCEmotions_States;
```

## Callback shapes

### PhysiologicalStates

```c
// States update (fires every ~2 min)
typedef void (*clCPhysiologicalStates_StatesUpdateHandler)(
    clCPhysiologicalStates, const clCPhysiologicalStates_Value*) NOEXCEPT;

// Calibration complete (fires once, passes baselines struct)
typedef void (*clCPhysiologicalStates_CalibratedHandler)(
    clCPhysiologicalStates, const clCPhysiologicalStates_Baselines*) NOEXCEPT;

// Calibration progress (passes float directly, assumed 0.0–1.0)
typedef void (*clCPhysiologicalStates_CalibrationProgressUpdateHandler)(
    clCPhysiologicalStates, float progress) NOEXCEPT;

// Individual NFB update (no data — just signal that NFB state changed)
typedef void (*clCPhysiologicalStates_IndividualNFBUpdateHandler)(
    clCPhysiologicalStates) NOEXCEPT;
```

**`IndividualNFBUpdateHandler` passes NO data** — only the handle. The bridge should emit an empty event or a fixed map on this channel to signal the update.

### Emotions

```c
typedef void (*clCEmotions_EmotionalStatesUpdateEvent)(
    clCEmotions, const clCEmotions_States*) NOEXCEPT;

typedef void (*clCEmotions_ErrorHandler)(
    clCEmotions, const char* message) NOEXCEPT;
```

## NFB dependency

**PhysiologicalStates:** Internally depends on NFB signal processing — `nfbArtifacts` field and `SetOnIndividualNFBUpdateEvent` callback confirm this. The SDK likely creates an internal NFB instance. Do NOT create a separate `NfbClassifier` just for Physio — just pass the device handle to `clCPhysiologicalStates_Create`.

**Emotions:** No NFB-related fields or callbacks in the API. Likely independent of NFB at the C API level, despite Dart docs saying "internally uses NFB alpha decomposition." The C API creates Emotions from device handle alone with no NFB dependency visible.

## Dart map shapes

### PhysiologicalStates state event
```
{
  'ts':               Int64
  'relaxation':       Double or null (sentinel pattern)
  'fatigue':          Double or null
  'none':             Double or null
  'concentration':    Double or null
  'involvement':      Double or null
  'stress':           Double or null
  'nfbArtifacts':     Bool
  'cardioArtifacts':  Bool
}
```

### PhysiologicalStates calibrated event (baselines)
```
{
  'ts':               Int64
  'alpha':            Double or null
  'beta':             Double or null
  'alphaGravity':     Double or null
  'betaGravity':      Double or null
  'concentration':    Double or null
}
```

### Emotions state event
```
{
  'ts':               Int64
  'attention':        Double or null
  'relaxation':       Double or null
  'cognitiveLoad':    Double or null
  'cognitiveControl': Double or null
  'selfControl':      Double or null
}
```

## Resolved

1. **`IndividualNFBUpdateEvent` ordering:** `CalibratedHandler` (line 42) and `IndividualNFBUpdateHandler` (line 48) are independent events. `IndividualNFBUpdateEvent` signals that NFB data inside the classifier has refreshed — unrelated to baselines calibration completion. Bridge emits empty map `{}` on this event; Dart side treats it as a notification signal only.
2. **`ImportBaselines` silent failure:** No error param confirmed (`CPhysiologicalStates.h`). Dart `PhysioClassifier.importBaselines()` should validate all 6 fields are non-null before invoking the bridge. Bridge itself has no way to report failure.
3. **Calibration progress range:** `CPhysiologicalStates.h:45` — callback `(clCPhysiologicalStates, float)`. No documented range. Treat as 0.0–1.0; bridge should clamp: `max(0.0, min(1.0, value))` before emitting.
