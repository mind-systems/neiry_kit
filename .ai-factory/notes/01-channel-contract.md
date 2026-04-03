# Dart Channel Contract

**Date:** 2026-04-03
**Source:** SDK docs — get_started, connect_to_device, devices_modes, capsule_flow, _c_device_locator_8h, _c_device_8h

## Key Findings

- 8 MethodChannels needed: `device_locator`, `device`, `nfb`, `physiological`, `emotions`, `productivity`, `cardio`, `nfb_calibrator`
- 22 EventChannels needed: device list, EEG, PSD, artifacts, resistance, battery, connection status, mode, 4 classifier outputs, 1 nfb calibration (sealed CalibrationEvent), 2 physio/productivity calibration streams, error streams
- Device discovery is event-based, not poll-based — fires exactly once when scan completes
- All callback registrations are implicit (handled via EventChannel `onListen`); no `setOn*` method names needed in the channel contract
- Calibration data (baselines for Physio/Productivity, IndividualNFBData) must be treated as opaque blobs — Dart should not parse them

## Details

### MethodChannel IDs

```
neiry_kit/device_locator
neiry_kit/device
neiry_kit/nfb
neiry_kit/physiological
neiry_kit/emotions
neiry_kit/productivity
neiry_kit/cardio
neiry_kit/nfb_calibrator
```

### Method Names

DeviceLocator: `requestDevices`, `setSingleThreaded`, `setLogLevel`, `getVersionString`

Device: `createDevice`, `connect`, `disconnect`, `start`, `stop`, `getMode`, `isConnected`, `getBatteryCharge`, `getInfo`, `getEEGSampleRate`, `getPPGSampleRate`, `getMEMSSampleRate`, `getPPGIrAmplitude`, `getPPGRedAmplitude`, `getChannelNames`, `getChannelIndexByName`, `getChannelNameByIndex`, `getChannelsCount`

Classifiers (shared pattern): `create`, `createCalibrated` (NFB/Cardio), `startBaselineCalibration`, `stopBaselineCalibration`, `importBaselines`, `resetAccumulatedFatigue` (Productivity only)

NFB Calibrator: `startCalibration`, `stopCalibration`; also `importCalibration`, `getCalibration`, `isCalibrated`

### EventChannel IDs

```
neiry_kit/events/deviceList
neiry_kit/events/eeg
neiry_kit/events/psd
neiry_kit/events/eegArtifacts
neiry_kit/events/resistance
neiry_kit/events/battery
neiry_kit/events/connectionStatus
neiry_kit/events/modeSwitched
neiry_kit/events/nfbState
neiry_kit/events/physiologicalState
neiry_kit/events/emotionsState
neiry_kit/events/productivityMetrics
neiry_kit/events/productivityIndexes
neiry_kit/events/cardioData
neiry_kit/events/ppgData
neiry_kit/events/memsData
neiry_kit/events/nfbCalibration
neiry_kit/events/physiologicalCalibrationProgress
neiry_kit/events/physiologicalCalibrated
neiry_kit/events/productivityCalibrationProgress
neiry_kit/events/productivityCalibrated
neiry_kit/events/cardioCalibratedEvent
neiry_kit/events/error
neiry_kit/events/nfbError
neiry_kit/events/emotionsError
neiry_kit/events/productivityError
```

### Argument Keys

```
serial, deviceType, searchTime, mode, level, enabled,
baselines, calibrationData, calibratorData, channelName, index
```

### Device Type Enum Values
`Headband=0, Buds=1, Headphones=2, Impulse=3, Any=4, BrainBit=6, SinWave=100, Noise=101`

### Device Mode Enum Values
`Resistance=0, Signal=1, SignalAndResist=2, StartMEMS=3, StopMEMS=4, StartPPG=5 (or 6), StopPPG=6 (or 7)`

### Connection State Enum Values
`Disconnected=0, Connected=1, UnsupportedConnection=2`

## Open Questions

- Cardio channel ID for calibration — docs show `cardioCalibratedEvent` but exact channel name needs confirmation from `_c_cardio_8h`
- Device mode enum ordinal values need verification (Start/StopPPG indices conflict in different docs)
- Single-threaded mode support: if enabled, Dart needs a `Timer` to call `update()` periodically — determine if this is in scope for v1
