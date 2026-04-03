# Project: neiry_kit

## Overview

A Flutter plugin that wraps the Neiry Capsule neurofeedback SDK for iOS and Android. It exposes a clean Dart API for BCI (brain-computer interface) features — device discovery, EEG streaming, impedance checking, and all classifiers (NFB, physiological states, emotions, productivity, cardio). Platform implementations bridge Dart to the native C SDK via Flutter MethodChannel and EventChannel. An example app exercises every feature end-to-end for hardware verification before integration into `mind_mobile`.

## Core Features

- Device discovery and connection lifecycle (BLE scan, connect, disconnect)
- EEG, PSD, MEMS, and PPG data streaming
- Electrode impedance (resistance) checking
- NFB brain-wave classifier with individual calibration
- Physiological states classifier (relaxation, fatigue, concentration, involvement, stress)
- Emotions classifier (attention, relaxation, cognitive load, cognitive control, self-control)
- Productivity classifier with fatigue metrics and baselines
- Individual NFB calibration pipeline (4-stage or quick mode)
- Battery charge monitoring
- Thread model control (multi-threaded default, single-threaded with Update pump)
- SDK version and log level control

## Tech Stack

- **Language:** Dart (plugin API) + Swift/Kotlin (platform channel implementations)
- **Framework:** Flutter plugin
- **Native SDK:** Capsule/Neiry C SDK (C API, `clC*` prefix)
  - iOS: `CapsuleClient.framework` (XCFramework, arm64, iOS 13.0+)
  - Android: `CapsuleService.aar` + `devicedriver.aar`
- **Bridge pattern:** Flutter MethodChannel (commands) + EventChannel (data streams)
- **State management (example app):** Riverpod
- **Consumer:** `mind_mobile` will add this plugin as a path/pub dependency

## SDK API Surface

### Device lifecycle
| C function | Purpose |
|---|---|
| `clCDeviceLocator_Create` | Create locator, entry point |
| `clCDeviceLocator_RequestDevices` | Start BLE scan |
| `clCDeviceLocator_SetOnDeviceListEvent` | Callback: device list ready |
| `clCDeviceLocator_CreateDevice` | Create device handle from serial |
| `clCDevice_Connect(bipolar)` | Non-blocking BLE connect |
| `clCDevice_Start` / `clCDevice_Stop` | Start/stop EEG streaming |
| `clCDevice_Disconnect` / `clCDevice_Release` | Disconnect and release |

### Data streams
| C handler | Dart stream | Data fields |
|---|---|---|
| `SetOnEEGDataEvent` | `eegStream` | `clCEEGTimedData` |
| `SetOnPSDDataEvent` | `psdStream` | `clCPSDData` |
| `SetOnEEGArtifactsEvent` | `artifactsStream` | `clCEEGArtifacts` |
| `SetOnResistanceUpdateEvent` | `resistanceStream` | `clCResistance` |
| `SetOnBatteryChargeUpdateEvent` | `batteryStream` | `uint8_t` |

### Classifiers
| C type | Dart class | Key output struct |
|---|---|---|
| `clCNFB` | `NfbClassifier` | `clCNFB_UserState` (delta, theta, alpha, smr, beta) |
| `clCPhysiologicalStates` | `PhysioClassifier` | `clCPhysiologicalStates_Value` (relaxation, fatigue, concentration, involvement, stress) |
| `clCEmotions` | `EmotionsClassifier` | `clCEmotions_States` (attention, relaxation, cognitiveLoad, cognitiveControl, selfControl) |
| `clCProductivity` | `ProductivityClassifier` | `clCProductivity_Metrics` + `_Indexes` + `_Baselines` |

### NFB Calibration
`clCNFBCalibrator` — 4-stage or quick calibration; produces `clCIndividualNFBData` (individual frequency, bandwidth, power bounds) used by NFB, Productivity, and Emotions classifiers.

## Architecture Notes

- The plugin follows the standard Flutter federated plugin layout: `lib/` (Dart API), `ios/` (Swift bridging), `android/` (Kotlin bridging).
- All SDK callbacks arrive on a background thread — the native side must marshal data before sending via EventChannel (which is thread-safe).
- Sentinel value `-1` / `-1.F` means "not yet available" across all structs.
- Device type enum: `Headband`, `Buds`, `Headphones`, `Impulse`, `BrainBit`, `Any`; `SinWave`/`Noise` are simulators.
- `official/` directory contains vendored binaries — never modify.

## Architecture
See `.ai-factory/ARCHITECTURE.md` for detailed architecture guidelines.
Pattern: Flutter Federated Plugin — Layered SDK Bridge

## Non-Functional Requirements

- Logging: expose `clCCapsule_SetLogLevel` through Dart so the app can control SDK verbosity
- Error handling: propagate `clCError` as typed Dart exceptions
- Thread safety: all EventChannel sinks must be called on the platform thread
- Min targets: iOS 13.0, Android (TBD based on AAR requirements)
