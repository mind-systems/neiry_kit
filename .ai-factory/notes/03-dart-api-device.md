# Dart API — DeviceLocator and Device

**Date:** 2026-04-03
**Source:** SDK docs — get_started, connect_to_device, capsule_flow, classcapsule DeviceLocator/Device, _c_device_locator_8h, _c_device_8h

## Key Findings

- `DeviceLocator` is a singleton — create once, reuse for multiple scans
- `requestDevices` is non-blocking; results arrive via EventChannel, fires exactly once
- `Device::connect` takes a `bipolarChannels` bool — channels are combined pairwise when true
- All sample rates (EEG, PPG, MEMS) are device-specific and must be queried AFTER connect
- Subscribe to streams BEFORE calling `start()` to avoid missing early packets
- `getChannelNames()` is device-dependent — Band, Buds, Headphones have different configs

## Details

### DeviceLocator API

```dart
class DeviceLocator {
  factory DeviceLocator({String? logDirectory})  // clCDeviceLocator_Create[WithLogDirectory]
  void update()                                    // single-threaded mode only
  bool get isValid
  void dispose()                                   // clCDeviceLocator_Destroy

  Stream<List<DeviceInfo>> requestDevices({        // clCDeviceLocator_RequestDevices
    DeviceType type = DeviceType.any,
    int searchTime = 5,
  })

  Future<Device> createDevice(String serial)       // clCDeviceLocator_CreateDevice
}
```

Discovery stream emits once with full list then completes. If Bluetooth disabled, emits error.

### Device Lifecycle State Machine

```
Created → connect() → Connected → start() → Started (streams active)
                   ← disconnect()          ← stop()
```

Invariants enforced by Dart API:
- `start()` before classifiers — throws `DeviceNotStartedException` otherwise
- `connect()` before `start()` — throws `DeviceNotConnectedException` otherwise

### Device API

```dart
class Device {
  Future<void> connect({bool bipolarChannels = false})  // clCDevice_Connect
  Future<void> disconnect()                              // clCDevice_Disconnect
  Future<void> start()                                   // clCDevice_Start
  Future<bool> stop()                                    // clCDevice_Stop
  
  Stream<ConnectionState> get connectionStateStream      // EventChannel
  Stream<DeviceMode> get modeChangedStream               // EventChannel

  Stream<EEGData> get eegStream                         // clCDevice_SetOnEEGDataEvent
  Stream<PSDData> get psdStream                         // clCDevice_SetOnPSDDataEvent
  Stream<EEGArtifactData> get artifactsStream           // clCDevice_SetOnEEGArtifactsEvent
  Stream<ResistanceData> get resistanceStream           // clCDevice_SetOnResistanceUpdateEvent
  Stream<int> get batteryStream                         // clCDevice_SetOnBatteryChargeUpdateEvent
  Stream<String> get errorStream                        // clCDevice_SetOnErrorEvent

  Future<DeviceInfo> getInfo()
  int? get battery                                       // clCDevice_GetBatteryCharge (cached)
  DeviceMode get mode                                    // cached from last event

  Future<double> getEEGSampleRate()
  Future<double> getPPGSampleRate()
  Future<double> getMEMSSampleRate()
  Future<int> getPPGIrAmplitude()
  Future<int> getPPGRedAmplitude()
  Future<List<String>> getChannelNames()
  Future<int> getChannelIndex(String channelName)
  
  bool get isValid
  void dispose()                                         // clCDevice_Release
}
```

### EEGData structure

- `rawValues: List<List<double>>` — [channel][sample], microvolts
- `processedValues: List<List<double>>` — artifact-filtered, empty in Resistance mode
- `channelCount`, `sampleCount` — device-specific
- Typical sample rate: 250 Hz

### ResistanceData

- Per-channel: `List<(String name, double kOhm)>`
- Fires per channel independently, not as a batch
- Good contact: < 500 kΩ

### DeviceType enum

```dart
enum DeviceType { headband, buds, headphones, impulse, any, brainBit, sinWave, noise }
```

### DeviceMode enum

```dart
enum DeviceMode { resistance, signal, signalAndResist, startMEMS, stopMEMS, startPPG, stopPPG }
```

### ConnectionState enum

```dart
enum ConnectionState { disconnected, connected, unsupportedConnection }
```

### NeiryErrorCode (16 values)

`ok, failedToConnect, failedToInitConnection, failedToInitialize, deviceError, individualNFBNotCalibrated, notReceived, nullPointer, moduleAlreadyExists, moduleNotSupported, failedToSendData, indexOutOfRange, emptyCollection, notFound, sizeMismatch, unknownEnum, bluetoothDisabled, unknown`

### Cleanup order

```dart
await device.stop();
await device.disconnect();
device.dispose();
deviceLocator.dispose();
```
