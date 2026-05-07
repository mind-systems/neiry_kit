# SDK v2.0.72 — C API Header Diff

## Verdict: No breaking changes

All existing C function signatures, struct layouts, and enum values are identical between the old vendored SDK and v2.0.72. Our iOS Swift and Android JNI bridges require zero modifications to work with the new binaries.

## One new function added

**CDevice.h** — additive only:

```c
const char* clCDevice_GetFirmwareVersion(clCDevice device, clCError* error) NOEXCEPT;
```

Returns firmware version string (only populated after device is connected). Not currently exposed in our Dart API. Optional to add.

## Verified unchanged

- All `clCDeviceLocator_*` functions (including `clCDeviceLocator_CreateDevice` — NOT renamed)
- All `clCDevice_*` connection/streaming functions
- All classifier create/event functions (NFB, Physio, Emotions, Productivity, Cardio, MEMS)
- All structs: `clCError`, `clCCardio_Data`, `clCEmotions_States`, `clCPhysiologicalStates_Value/Baselines`, `clCProductivity_Metrics/Indexes/Baselines`, `clCIndividualNFBData`, `clCNFB_UserState`, `clCPoint3d`
- All enums: `clCDeviceType`, `clCDevice_Mode`, `clCDevice_ConnectionStatus`, `clCError_Code`, all classifier enums

## Action required

Replace vendored binaries:
- `official/iOS/CapsuleClient.framework` → `official/Capsule v2.0.72/CapsuleAPI/iOS/CapsuleClient.framework`
- `official/Android/CapsuleService.aar` → `official/Capsule v2.0.72/CapsuleAPI/Android/CapsuleService.aar`
- `official/Android/devicedriver.aar` → `official/Capsule v2.0.72/CapsuleAPI/Android/devicedriver.aar`

No code changes needed alongside the binary swap.
