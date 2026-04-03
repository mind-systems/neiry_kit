# AGENTS.md

> Project map for AI agents. Keep this file up-to-date as the project evolves.

## Project Overview

Flutter plugin wrapping the Neiry Capsule BCI/neurofeedback SDK for iOS (XCFramework) and Android (AAR). Exposes a Dart API for device discovery, EEG streaming, and all classifiers (NFB, physiological states, emotions, productivity) via Flutter platform channels.

## Tech Stack

- **Language:** Dart (API layer) + Swift (iOS platform) + Kotlin (Android platform)
- **Framework:** Flutter federated plugin
- **Native SDK:** Capsule C API (`clC*` prefix) — iOS XCFramework, Android AAR
- **Bridge:** Flutter MethodChannel (commands) + EventChannel (streams)
- **Example app state management:** Riverpod

## Project Structure

```
neiry_kit/
  lib/                     # Dart public API (MethodChannel calls, EventChannel streams, data models)
  ios/                     # Swift platform channel implementation bridging to C SDK
  android/                 # Kotlin platform channel implementation bridging to C SDK
  example/                 # Standalone Flutter app exercising all SDK features on real hardware
  official/                # Vendored binary artifacts — DO NOT MODIFY
    iOS/
      CapsuleClient.framework/   # XCFramework (arm64, iOS 13.0+)
        Headers/                 # C API headers (CCapsuleAPI.h is the entry point)
    Android/
      CapsuleService.aar         # Main SDK library
      devicedriver.aar           # BLE device driver
    Docs/html/                   # Doxygen-generated API reference
  .ai-factory/             # AI agent context
    DESCRIPTION.md         # Project specification and full SDK API surface
    ARCHITECTURE.md        # Architecture decisions and code structure (generated)
    plans/                 # Implementation plans
```

## Key Entry Points

| File | Purpose |
|------|---------|
| `official/iOS/CapsuleClient.framework/Headers/CCapsuleAPI.h` | Master C header (includes all sub-headers) |
| `official/iOS/CapsuleClient.framework/Headers/CDeviceLocator.h` | Device discovery + threading control |
| `official/iOS/CapsuleClient.framework/Headers/CDevice.h` | Device connect/stream/info |
| `official/iOS/CapsuleClient.framework/Headers/CNFB.h` | NFB classifier |
| `official/iOS/CapsuleClient.framework/Headers/CNFBCalibrator.h` | Individual NFB calibration |
| `official/iOS/CapsuleClient.framework/Headers/CPhysiologicalStates.h` | Physio classifier |
| `official/iOS/CapsuleClient.framework/Headers/CEmotions.h` | Emotions classifier |
| `official/iOS/CapsuleClient.framework/Headers/CProductivity.h` | Productivity classifier |

## Documentation

| Document | Path | Description |
|----------|------|-------------|
| README | README.md | Project landing page |
| Device lifecycle | docs/device-lifecycle.md | Search, connect, start, stop |
| Data streams | docs/data-streams.md | EEG, PSD, artifacts, resistance, battery |
| Classifiers | docs/classifiers.md | NFB, physio, emotions, productivity, cardio |
| NFB calibration | docs/calibration.md | 4-stage pipeline, quick mode, IndividualNfbData |
| Example app | docs/example-app.md | What the example app covers and how to use it |
| CLAUDE.md | CLAUDE.md | Agent instructions, SDK concepts, integration flow |
| SDK API reference | official/Docs/html/ | Doxygen HTML, authoritative C API docs |

## AI Context Files

| File | Purpose |
|------|---------|
| AGENTS.md | This file — project structure map |
| .ai-factory/DESCRIPTION.md | Full project spec, SDK API surface mapping, Dart↔C correspondence |
| .ai-factory/ARCHITECTURE.md | Architecture decisions and code patterns |
| CLAUDE.md | SDK architecture, integration flow, threading model, data types |
