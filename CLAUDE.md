# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`neiry_kit` is a **Flutter plugin** that wraps the native Neiry/Capsule neurofeedback SDK for iOS and Android, plus an example app to test all functionality end-to-end before integrating into `mind_mobile`.

Vendored binary artifacts live in `official/` (do not modify):
- `official/iOS/CapsuleClient.framework` — iOS XCFramework (arm64, iOS 13.0+, built with Xcode 15)
- `official/Android/CapsuleService.aar` + `devicedriver.aar` — Android AAR libraries
- `official/Docs/html/` — Doxygen-generated API reference

## SDK architecture

The Capsule SDK is a C/C++ library exposed via two parallel API surfaces:

**C API** (`clC*` prefix) — plain C, ABI-stable, use from Dart FFI, Swift, or any language that can call C. Entry point is `CCapsuleAPI.h` which includes all C headers.

**C++ API** (`capsule::client` namespace) — RAII wrappers around the C API, prefer this when writing native C++ integration code.

### Core concepts and their types

| Concept | C type | C++ type |
|---|---|---|
| Device discovery | `clCDeviceLocator` | `DeviceLocator` |
| Device handle | `clCDevice` | `Device` |
| Raw EEG stream | `clCEEGTimedData` | `device::EEGTimedData` |
| Power spectral density | `clCPSDData` | `device::PSDData` |
| Motion sensor (MEMS) | `clCMEMSTimedData` | — |
| Photoplethysmography (PPG) | `clCPPGTimedData` | — |
| Impedance check | `clCResistance` | `device::Resistances` |
| NFB brain-wave classifier | `clCNFB` | `ClassificationNFB` |
| Physiological states | `clCPhysiologicalStates` | `ClassificationPhysiologicalStates` |
| Emotions classifier | `clCEmotions` | `ClassificationEmotions` |
| Productivity classifier | `clCProductivity` | `ClassificationProductivity` |
| Cardio classifier | — | `ClassificationCardio` |
| Individual NFB calibration | `clCNFBCalibrator` | `NFBCalibrator` |

### Typical integration flow

1. **Discover** — create `DeviceLocator`, call `RequestDevices(deviceType, searchTime)`, receive device list via `SetOnDeviceListEvent` callback.
2. **Connect** — call `CreateDevice(serial)`, then `Device::Connect(bipolarChannels)`. Connection is non-blocking; wait for `SetOnConnectionStateChangedEvent`.
3. **Resistance check** — before streaming EEG, optionally verify electrode contact via `SetOnResistanceUpdateEvent` while device is in `Resistance` mode.
4. **Start streaming** — call `Device::Start()`, subscribe to `SetOnEEGDataEvent` / `SetOnPSDDataEvent` / `SetOnEEGArtifactsEvent`.
5. **Classification** — instantiate a classifier (e.g., `ClassificationPhysiologicalStates(device)`), subscribe to its update event. Many classifiers need a baseline calibration step before emitting valid values; call `StartBaselineCalibration()` and wait for the calibrated callback.
6. **Individual NFB calibration** — for NFB/Productivity/Emotions classifiers, run `NFBCalibrator` through its stages (1–4 or quick mode) first, then create classifiers with the calibrated data.
7. **Stop and release** — call `Device::Stop()`, `Device::Disconnect()`, then release the locator.

### Threading model

By default the SDK fires all callbacks on a **background thread**. Call `DeviceLocator::SetSingleThreaded(true)` once at startup to switch to single-threaded mode, then pump `DeviceLocator::Update()` from the main thread each frame.

### Signal data

- EEG sample rate, PPG sample rate, and MEMS sample rate are device-specific — query via `GetEEGSampleRate()` etc. after connecting.
- NFB user state carries per-band power: `delta`, `theta`, `alpha`, `smr`, `beta` (float, 0–1 normalized range, -1 means no data yet).
- Physiological states output: `relaxation`, `fatigue`, `concentration`, `involvement`, `stress`, `none` (float 0–1, -1 = no data).
- Emotions output: `attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl`.
- All structs use `-1.F` / `-1` as sentinel for "not yet available".

### Supported device types

`clCDeviceType`: `Headband`, `Buds`, `Headphones`, `Impulse`, `BrainBit`, `Any`. `SinWave` and `Noise` are simulator types for testing without hardware.

## Plugin structure (target layout)

```
neiry_kit/
  lib/                     # Dart public API
  android/                 # Android platform channel implementation (Kotlin)
  ios/                     # iOS platform channel implementation (Swift/ObjC)
  example/                 # Standalone Flutter app to exercise all SDK features
```

The plugin exposes a Dart API that mirrors the SDK concepts above. Platform implementations bridge via Flutter **platform channels** (MethodChannel / EventChannel) to the native C/C++ SDK. The example app must cover every classifier and the full device lifecycle so that each feature can be verified on real hardware before `mind_mobile` consumes the API.

## Commands

```bash
# Run the example app
cd example && flutter run

# Run tests
flutter test

# Analyze
flutter analyze

# Generate code (if using build_runner for FFI bindings or freezed models)
dart run build_runner build --delete-conflicting-outputs
```

## Documentation

| Guide | Path |
|---|---|
| Documentation landing page (streams, classifiers, session flow) | `docs/overview.md` |
| Project setup (deps, permissions, iOS plist) | `docs/guides/setup.md` |
| Full session walkthrough | `docs/guides/session-guide.md` |
| Teardown sequence & SDK invariants | `docs/guides/teardown.md` |
| Error handling & exception types | `docs/guides/error-handling.md` |
| Example app structure | `docs/guides/example-app.md` |
| Device lifecycle (DeviceLocator, Device) | `docs/reference/device-lifecycle.md` |
| Data streams (EEG, PSD, resistance, battery) | `docs/reference/data-streams.md` |
| Classifiers (NFB, physio, emotions, productivity, cardio, MEMS) | `docs/reference/classifiers.md` |
| NFB calibration | `docs/reference/calibration.md` |

## Integration into mind_mobile

Once the Dart API is stable here, `mind_mobile` adds `neiry_kit` as a path or pub dependency. Do not copy native binaries — they live here only.
