# Architecture: Flutter Federated Plugin — Layered SDK Bridge

## Overview

neiry_kit follows the standard Flutter federated plugin layout, adapted for a native C SDK bridge. The plugin is organized into three horizontal layers: a Dart public API, a platform channel contract, and native platform implementations (Swift/Kotlin) that call the Capsule C API.

This layered approach was chosen because the domain is purely SDK wrapping — there is no complex business logic, no database, and no need for dependency inversion or bounded contexts. The goal is a thin, predictable bridge that maps the C API 1:1 to idiomatic Dart constructs while hiding all native complexity from `mind_mobile`.

## Decision Rationale

- **Project type:** Flutter plugin (SDK wrapper)
- **Tech stack:** Dart + Swift (iOS) + Kotlin (Android) + C API
- **Key factor:** Flutter plugin conventions are the primary constraint. The C API surface defines the feature set completely — the architecture only needs to map it cleanly.

## Folder Structure

```
neiry_kit/
  lib/
    src/
      api/                     # Public Dart classes (one file per C concept)
        device_locator.dart    # Wraps CDeviceLocator — discovery, threading control
        device.dart            # Wraps CDevice — connect, stream, info, battery
        classifiers/
          nfb_classifier.dart
          physio_classifier.dart
          emotions_classifier.dart
          productivity_classifier.dart
      models/                  # Immutable Dart data classes (mirrors C structs)
        eeg_data.dart
        psd_data.dart
        nfb_user_state.dart
        physio_states.dart
        emotions_states.dart
        productivity_metrics.dart
        device_info.dart
        individual_nfb_data.dart
        resistance.dart
      channel/                 # Platform channel contract (method names, argument keys)
        channel_names.dart     # Constants: channel IDs, method names, event channel IDs
        codec.dart             # Encode/decode Map ↔ Dart model (shared with platform)
    neiry_kit.dart             # Barrel export — everything public re-exported here
  ios/
    Classes/
      NeiryKitPlugin.swift     # FlutterPlugin entry point, registers all channels
      DeviceLocatorBridge.swift
      DeviceBridge.swift
      classifiers/
        NfbBridge.swift
        PhysioBridge.swift
        EmotionsBridge.swift
        ProductivityBridge.swift
      NfbCalibratorBridge.swift
  android/
    src/main/kotlin/.../
      NeiryKitPlugin.kt
      DeviceLocatorBridge.kt
      DeviceBridge.kt
      classifiers/
        NfbBridge.kt
        ...
  example/
    lib/
      main.dart
      screens/                 # One screen per feature group
        discovery_screen.dart
        streaming_screen.dart
        classifiers_screen.dart
        calibration_screen.dart
      providers/               # Riverpod providers
  official/                   # Vendored SDK — never modified
```

## Dependency Rules

```
lib/src/api/        →  lib/src/channel/  (sends method calls, listens to event streams)
lib/src/api/        →  lib/src/models/   (returns typed Dart models)
lib/src/channel/    →  nothing           (pure constants + codecs)
ios/Classes/        →  official/iOS/     (calls C API directly)
android/src/        →  official/Android/ (calls SDK via AAR)
example/            →  lib/              (uses public Dart API only)
```

- ✅ `example/` depends on `lib/` public API only
- ✅ Platform code (`ios/`, `android/`) depends on C SDK and Flutter engine only
- ✅ `lib/src/api/` depends on `lib/src/channel/` (constants) and `lib/src/models/`
- ❌ `lib/` must never import anything from `ios/` or `android/`
- ❌ `example/` must never import from `lib/src/` directly — only via the barrel `neiry_kit.dart`
- ❌ Platform bridges must never cross-call each other (each bridge owns its own channels)

## Layer Communication

**Dart → Native (commands):** `MethodChannel` calls with a `String` method name and `Map<String, dynamic>` arguments. Returns a `Map<String, dynamic>` or throws `PlatformException`.

**Native → Dart (streams):** `EventChannel` per data source (one per event type: EEG, PSD, artifacts, resistance, battery, NFB state, physio states, emotions, productivity metrics, calibration progress, etc.). The native side calls `eventSink.success(map)` from the SDK callback; the Dart side maps the raw `Map` to a typed model via `codec.dart`.

**Error propagation:** C `clCError` is caught by native code and thrown as `PlatformException(code: errorCode, message: errorMessage)`. The Dart API catches `PlatformException` and re-throws as typed `NeiryException` subclasses.

**Threading:** SDK callbacks arrive on a background thread. Native bridges must capture the `FlutterEventSink` and dispatch to the platform thread (iOS: `DispatchQueue.main`, Android: `Handler(Looper.getMainLooper())`) before calling `sink.success()`.

## Key Principles

1. **One bridge class per C API module.** `DeviceLocatorBridge` wraps `clCDeviceLocator_*`, `DeviceBridge` wraps `clCDevice_*`, etc. No bridge handles two unrelated C modules.

2. **Models are immutable value types.** All Dart models are `@immutable` classes with named constructors or `fromMap` factories. No mutable state in models.

3. **Channel constants are the contract.** Method names, argument keys, and event channel IDs are defined in `channel/channel_names.dart` and imported by both the Dart API layer and the native bridges. String literals are never duplicated.

4. **The barrel export is the public API.** `neiry_kit.dart` exports only what `mind_mobile` needs. Internal `src/` classes are not re-exported.

5. **Sentinel -1 is mapped to null at the Dart boundary.** Native codec translates `-1` / `-1.0` to `null` for all classifier outputs so Dart consumers use null-safety instead of magic numbers.

6. **Example app covers every feature.** Every classifier, every calibration stage, and every stream must have a corresponding screen in the example app. This is the integration test.

## Code Examples

### Dart API — DeviceLocator

```dart
// lib/src/api/device_locator.dart
class DeviceLocator {
  static const _channel = MethodChannel(ChannelNames.deviceLocator);

  /// Scans for devices of [type] for [searchTime] seconds.
  /// Returns via [onDeviceList] callback (fires once, on complete).
  static Stream<List<DeviceInfo>> requestDevices({
    DeviceType type = DeviceType.any,
    int searchTime = 5,
  }) {
    return const EventChannel(ChannelNames.deviceListEvent)
        .receiveBroadcastStream({
          'deviceType': type.index,
          'searchTime': searchTime,
        })
        .map((raw) => (raw as List)
            .map((e) => DeviceInfo.fromMap(e as Map))
            .toList());
  }

  static Future<Device> createDevice(String serial) async {
    await _channel.invokeMethod(ChannelNames.createDevice, {'serial': serial});
    return Device(serial: serial);
  }
}
```

### Channel constants — shared contract

```dart
// lib/src/channel/channel_names.dart
abstract final class ChannelNames {
  static const deviceLocator       = 'neiry_kit/device_locator';
  static const device              = 'neiry_kit/device';
  static const nfb                 = 'neiry_kit/nfb';
  static const physio              = 'neiry_kit/physio';
  static const emotions            = 'neiry_kit/emotions';
  static const productivity        = 'neiry_kit/productivity';

  // Method names
  static const createDevice        = 'createDevice';
  static const connect             = 'connect';
  static const disconnect          = 'disconnect';
  static const start               = 'start';
  static const stop                = 'stop';

  // EventChannel IDs
  static const deviceListEvent     = 'neiry_kit/events/deviceList';
  static const eegDataEvent        = 'neiry_kit/events/eeg';
  static const psdDataEvent        = 'neiry_kit/events/psd';
  static const resistanceEvent     = 'neiry_kit/events/resistance';
  static const batteryEvent        = 'neiry_kit/events/battery';
  static const nfbStateEvent       = 'neiry_kit/events/nfbState';
  static const physioStateEvent    = 'neiry_kit/events/physioState';
  static const emotionsStateEvent  = 'neiry_kit/events/emotionsState';
  static const productivityMetrics = 'neiry_kit/events/productivityMetrics';
  static const calibrationProgress = 'neiry_kit/events/calibrationProgress';
}
```

### Dart model — sentinel → null at boundary

```dart
// lib/src/models/nfb_user_state.dart
@immutable
class NfbUserState {
  final DateTime timestamp;
  final double? delta;
  final double? theta;
  final double? alpha;
  final double? smr;
  final double? beta;

  const NfbUserState({
    required this.timestamp,
    this.delta,
    this.theta,
    this.alpha,
    this.smr,
    this.beta,
  });

  factory NfbUserState.fromMap(Map<Object?, Object?> map) {
    double? orNull(Object? v) =>
        v == null || (v as double) < 0 ? null : v;
    return NfbUserState(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      delta: orNull(map['delta']),
      theta: orNull(map['theta']),
      alpha: orNull(map['alpha']),
      smr:   orNull(map['smr']),
      beta:  orNull(map['beta']),
    );
  }
}
```

### iOS bridge — thread-safe EventChannel sink

```swift
// ios/Classes/DeviceBridge.swift
class DeviceBridge: NSObject, FlutterStreamHandler {
  private var eegSink: FlutterEventSink?
  private let device: OpaquePointer  // clCDevice

  func onListen(withArguments _: Any?, eventSink sink: @escaping FlutterEventSink) -> FlutterError? {
    eegSink = sink
    clCDevice_SetOnEEGDataEvent(device) { [weak self] _, data in
      guard let self, let sink = self.eegSink else { return }
      let map: [String: Any] = ["ts": data.timestampMilli, "samples": /* ... */]
      DispatchQueue.main.async { sink(map) }
    }
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    eegSink = nil
    return nil
  }
}
```

## Anti-Patterns

- ❌ **Calling platform channels from a background isolate** — MethodChannel and EventChannel must be used from the root isolate only
- ❌ **Exposing raw `Map` from the Dart API** — always return typed model classes; consumers must not parse maps
- ❌ **Registering callbacks with `@escaping` closures that capture strong self** — use `[weak self]` in all SDK callbacks to avoid retain cycles with the C SDK
- ❌ **Sharing a single MethodChannel for all bridges** — each bridge has its own channel ID to keep dispatch logic simple
- ❌ **Checking for `-1` sentinel in Dart code** — the codec layer must absorb sentinel-to-null conversion so API consumers never see it
- ❌ **Starting classifiers before `clCDevice_Start`** — classifiers require an active EEG stream; enforce this in the Dart API
