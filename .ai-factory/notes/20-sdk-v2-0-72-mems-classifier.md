# SDK v2.0.72 — MEMS Classifier Analysis

## What the MEMS classifier is

A motion sensor classifier that delivers accelerometer + gyroscope data batches from the device. Structurally identical to Cardio in terms of plugin architecture (create, optional calibrated variant, single event stream).

## C API

```c
// Creation
clCMEMS clCMEMS_Create(clCDevice device, clCError* error);
clCMEMS clCMEMS_CreateCalibrated(clCDevice device, clCNFBCalibrator calibrator, clCError* error);

// Event subscription
void clCMEMS_SetOnMEMSTimedDataUpdateEvent(clCMEMS mems, clCMEMS_TimedDataUpdateHandler handler, clCError* error);

// Data accessors (called inside callback)
int32_t    clCMEMSTimedData_GetCount(clCMEMSTimedData data);
clCPoint3d clCMEMSTimedData_GetAccelerometer(clCMEMSTimedData data, int32_t index);
clCPoint3d clCMEMSTimedData_GetGyroscope(clCMEMSTimedData data, int32_t index);
uint64_t   clCMEMSTimedData_GetTimestampMilli(clCMEMSTimedData data, int32_t index);

// Callback type
typedef void (*clCMEMS_TimedDataUpdateHandler)(clCMEMS, clCMEMSTimedData) NOEXCEPT;
```

## MEMSSample data

Each batch is a list of samples, each containing:
- `accelerometer: Point3d` (x, y, z as double) — accelerometer vector
- `gyroscope: Point3d` (x, y, z as double) — gyroscope vector
- `timestampMilli: int`

`Point3d` is already defined in our C headers as `clCPoint3d`.

## Current status in our plugin

**Partially scaffolded** — the data plumbing is missing but the infrastructure hints exist:
- `memsData` event channel ID defined in `channel_names.dart`
- `startMEMS(3)` / `stopMEMS(4)` device mode enums defined
- `getMEMSSampleRate()` implemented in iOS + Android bridges
- **No** `MEMSClassifier` Dart class
- **No** `MEMSBridge` iOS Swift class
- **No** `jni_mems.cpp` Android JNI

## Complexity vs Cardio

MEMS is ~60-70% of Cardio's complexity:
- Simpler data (3D vectors, no cardiac metrics, no PPG stream)
- Single event stream only
- Same callback threading pattern as all other classifiers
- Official Dart wrapper in v2.0.72 serves as complete reference

Estimated effort: ~10-15 hours across all three layers.

## Is MEMS needed for mind_mobile?

MEMS exposes raw accelerometer/gyroscope. Useful for motion artifact detection and activity context during sessions. Decision to add should be driven by mind_mobile requirements — not blocking.
