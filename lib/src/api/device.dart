import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

import '../channel/channel_names.dart';
import '../channel/enums.dart';
import '../models/device_info.dart';
import '../models/eeg_artifact_data.dart';
import '../models/eeg_data.dart';
import '../models/neiry_exception.dart';
import '../models/psd_data.dart';
import '../models/resistance_data.dart';

/// Wraps the native `clCDevice` lifecycle — connect, start, stop, disconnect —
/// and exposes typed data streams backed by EventChannels.
///
/// ## Concurrent subscription warning
///
/// Concurrent stream subscriptions across multiple [Device] instances are not
/// supported. All EventChannels use shared static channel names, and Flutter's
/// `EventChannel` supports only one active `receiveBroadcastStream` per channel
/// name at a time. Opening the same stream on two instances simultaneously will
/// cause the second subscription to receive events intended for the first.
///
/// ## State machine
///
/// `connect()` → `start()` → (stream data) → `stop()` → `disconnect()`
///
/// Methods guard against invalid state transitions and throw [StateError] or
/// [DeviceNotConnectedException] when called out of order.
class Device {
  /// Creates a [Device] for the given [serial].
  ///
  /// The native device handle must have already been created by
  /// `DeviceLocator.createDevice()` before any method is called.
  Device({required this.serial});

  /// Hardware serial number that identifies this device.
  final String serial;

  // ── Channels ───────────────────────────────────────────────────────────────

  static const _channel = MethodChannel(NeiryChannels.device);

  // ── State ──────────────────────────────────────────────────────────────────

  bool _disposed = false;
  bool _connected = false;
  bool _started = false;
  NeiryConnectionState _connectionState = NeiryConnectionState.disconnected;
  NeiryDeviceMode? _mode;
  int? _battery;
  List<StreamSubscription<dynamic>>? _stateSubscriptions;
  final Set<int> _loggedUnknownModeCodes = <int>{};

  // ── Cached streams ─────────────────────────────────────────────────────────
  // Initialised lazily so each receiveBroadcastStream is called at most once
  // per Device instance.

  late final Stream<NeiryConnectionState> _connectionStateStream =
      _eventStream(
    const EventChannel(NeiryEvents.connectionStatus),
    (map) => NeiryConnectionState.fromCode(map['state'] as int),
  );

  late final Stream<NeiryDeviceMode> _modeChangedStream = const EventChannel(
    NeiryEvents.modeSwitched,
  )
      .receiveBroadcastStream({NeiryArgs.serial: serial})
      .map<NeiryDeviceMode?>((raw) {
        final code = (raw as Map<Object?, Object?>)['mode'] as int;
        final mode = NeiryDeviceMode.fromCode(code);
        if (mode == null && _loggedUnknownModeCodes.add(code)) {
          log(
            'Ignoring unknown NeiryDeviceMode code $code from native SDK',
            name: 'neiry_kit',
          );
        }
        return mode;
      })
      .where((mode) => mode != null)
      .cast<NeiryDeviceMode>();

  late final Stream<EegData> _eegStream = _eventStream(
    const EventChannel(NeiryEvents.eeg),
    EegData.fromMap,
  );

  late final Stream<PsdData> _psdStream = _eventStream(
    const EventChannel(NeiryEvents.psd),
    PsdData.fromMap,
  );

  late final Stream<EegArtifactData> _artifactsStream = _eventStream(
    const EventChannel(NeiryEvents.eegArtifacts),
    EegArtifactData.fromMap,
  );

  late final Stream<ResistanceData> _resistanceStream = _eventStream(
    const EventChannel(NeiryEvents.resistance),
    ResistanceData.fromMap,
  );

  late final Stream<int> _batteryStream = _eventStream(
    const EventChannel(NeiryEvents.battery),
    (map) => map['charge'] as int,
  );

  late final Stream<String> _errorStream = _eventStream(
    const EventChannel(NeiryEvents.error),
    (map) => map['message'] as String,
  );

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Device has been disposed');
  }

  void _checkConnected() {
    if (!_connected) throw const DeviceNotConnectedException();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Stream<T> _eventStream<T>(
    EventChannel channel,
    T Function(Map<Object?, Object?>) decode,
  ) {
    return channel
        .receiveBroadcastStream({NeiryArgs.serial: serial})
        .map((raw) => decode(raw as Map<Object?, Object?>));
  }

  void _startStateTracking() {
    _stateSubscriptions = [
      _connectionStateStream.listen((state) {
        _connectionState = state;
        if (state == NeiryConnectionState.disconnected) {
          _connected = false;
          _started = false;
        }
      }),
      _modeChangedStream.listen((mode) {
        _mode = mode;
      }),
      _batteryStream.listen((charge) {
        _battery = charge;
      }),
    ];
  }

  void _stopStateTracking() {
    for (final sub in _stateSubscriptions ?? []) {
      sub.cancel();
    }
    _stateSubscriptions = null;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Connects to the device over BLE.
  ///
  /// Set [bipolarChannels] to `true` to enable bipolar channel mode.
  /// Completes when the native connect call is dispatched (non-blocking —
  /// listen to [connectionStateStream] to detect the actual connection event).
  Future<void> connect({bool bipolarChannels = false}) async {
    log('Device.connect — serial: $serial _disposed: $_disposed _connected: $_connected', name: 'neiry_kit');
    _checkNotDisposed();
    if (_connected) throw StateError('Device is already connected');
    await _channel.invokeMethod<void>(DeviceMethods.connect, {
      NeiryArgs.serial: serial,
      NeiryArgs.bipolarChannels: bipolarChannels,
    });
    _connected = true;
    _startStateTracking();
  }

  /// Unregisters all native SDK callbacks for this device.
  ///
  /// Must be called before cancelling fan-in subscriptions (which deletes JNI
  /// global refs) and before disposing classifiers (which access device state).
  /// Calling [stop] or [disconnect] afterwards is safe — they re-run unregister
  /// internally as a no-op.
  Future<void> unregisterCallbacks() async {
    _checkNotDisposed();
    await _channel.invokeMethod<void>(DeviceMethods.unregisterCallbacks, {
      NeiryArgs.serial: serial,
    });
  }

  /// Disconnects from the device.
  ///
  /// Cancels internal state subscriptions and resets all cached state.
  Future<void> disconnect() async {
    _checkNotDisposed();
    await _channel.invokeMethod<void>(DeviceMethods.disconnect, {
      NeiryArgs.serial: serial,
    });
    _stopStateTracking();
    _started = false;
    _connected = false;
    _connectionState = NeiryConnectionState.disconnected;
    _mode = null;
    _battery = null;
  }

  /// Starts EEG streaming on the connected device.
  ///
  /// Throws [DeviceNotConnectedException] when called before [connect].
  Future<void> start() async {
    _checkNotDisposed();
    _checkConnected();
    await _channel.invokeMethod<void>(DeviceMethods.start, {
      NeiryArgs.serial: serial,
    });
    _started = true;
  }

  /// Stops streaming without releasing the native device handle.
  ///
  /// Use this inside a disconnect sequence so that classifiers can still be
  /// disposed (they need the handle) before [disconnect] releases it.
  /// For a standalone Stop (no subsequent Disconnect), use [stop] instead —
  /// it releases the handle immediately to prevent stale GATT refs.
  Future<void> stopStream() async {
    _checkNotDisposed();
    await _channel.invokeMethod<void>(DeviceMethods.stopStream, {
      NeiryArgs.serial: serial,
    });
    _started = false;
  }

  /// Stops EEG streaming.
  ///
  /// Returns `true` if the native stop succeeded.
  Future<bool> stop() async {
    _checkNotDisposed();
    final result = await _channel.invokeMethod<bool>(DeviceMethods.stop, {
      NeiryArgs.serial: serial,
    });
    _started = false;
    return result ?? false;
  }

  /// Releases this device instance and disconnects if still connected.
  ///
  /// After [dispose], all method calls throw [StateError].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopStateTracking();
    // The Capsule SDK is NOT idempotent — calling native disconnect while a
    // prior disconnect is still completing its async GATT teardown corrupts
    // internal state and causes Fatal signal 64. Skip the native call when
    // already disconnected (_connected is false after disconnect() returns).
    if (_connected) {
      await _channel.invokeMethod<void>(DeviceMethods.disconnect, {
        NeiryArgs.serial: serial,
      });
    }
    _started = false;
    _connected = false;
    _connectionState = NeiryConnectionState.disconnected;
    _mode = null;
    _battery = null;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Emits connection state changes from the native SDK.
  Stream<NeiryConnectionState> get connectionStateStream {
    _checkNotDisposed();
    return _connectionStateStream;
  }

  /// Emits device mode changes (resistance, signal, PPG, MEMS, etc.).
  Stream<NeiryDeviceMode> get modeChangedStream {
    _checkNotDisposed();
    return _modeChangedStream;
  }

  /// Emits raw and filtered EEG sample batches.
  Stream<EegData> get eegStream {
    _checkNotDisposed();
    return _eegStream;
  }

  /// Emits power spectral density frames.
  Stream<PsdData> get psdStream {
    _checkNotDisposed();
    return _psdStream;
  }

  /// Emits per-channel artifact flags and signal quality metrics.
  Stream<EegArtifactData> get artifactsStream {
    _checkNotDisposed();
    return _artifactsStream;
  }

  /// Emits electrode resistance readings (available in Resistance mode).
  Stream<ResistanceData> get resistanceStream {
    _checkNotDisposed();
    return _resistanceStream;
  }

  /// Emits battery charge level (0–100).
  Stream<int> get batteryStream {
    _checkNotDisposed();
    return _batteryStream;
  }

  /// Emits error messages forwarded from the native SDK.
  Stream<String> get errorStream {
    _checkNotDisposed();
    return _errorStream;
  }

  // ── Sync getters ──────────────────────────────────────────────────────────

  /// Last known battery charge (0–100), or `null` before the first event.
  int? get battery => _battery;

  /// Last known device mode, or `null` before the first mode event.
  NeiryDeviceMode? get mode => _mode;

  /// Current connection state (updated from [connectionStateStream]).
  NeiryConnectionState get connectionState => _connectionState;

  /// Whether the device is currently connected.
  bool get isConnected => _connected;

  /// Whether EEG streaming is currently active.
  bool get isStarted => _started;

  /// Whether this [Device] instance has not been disposed.
  bool get isValid => !_disposed;

  // ── Async getters ─────────────────────────────────────────────────────────

  /// Fetches device hardware information from the native side.
  Future<DeviceInfo> getInfo() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<Object>(
      DeviceMethods.getInfo,
      {NeiryArgs.serial: serial},
    );
    return DeviceInfo.fromMap(result! as Map<Object?, Object?>);
  }

  /// Returns the EEG sample rate in Hz.
  Future<double> getEEGSampleRate() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<Object>(
      DeviceMethods.getEEGSampleRate,
      {NeiryArgs.serial: serial},
    );
    return (result! as num).toDouble();
  }

  /// Returns the PPG sample rate in Hz.
  Future<double> getPPGSampleRate() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<Object>(
      DeviceMethods.getPPGSampleRate,
      {NeiryArgs.serial: serial},
    );
    return (result! as num).toDouble();
  }

  /// Returns the MEMS (accelerometer/gyroscope) sample rate in Hz.
  Future<double> getMEMSSampleRate() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<Object>(
      DeviceMethods.getMEMSSampleRate,
      {NeiryArgs.serial: serial},
    );
    return (result! as num).toDouble();
  }

  /// Returns the PPG infrared LED amplitude.
  Future<int> getPPGIrAmplitude() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<int>(
      DeviceMethods.getPPGIrAmplitude,
      {NeiryArgs.serial: serial},
    );
    return result!;
  }

  /// Returns the PPG red LED amplitude.
  Future<int> getPPGRedAmplitude() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<int>(
      DeviceMethods.getPPGRedAmplitude,
      {NeiryArgs.serial: serial},
    );
    return result!;
  }

  /// Returns the list of electrode channel names.
  Future<List<String>> getChannelNames() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<Object>(
      DeviceMethods.getChannelNames,
      {NeiryArgs.serial: serial},
    );
    return (result! as List).map((e) => e as String).toList();
  }

  /// Returns the zero-based index of the channel named [channelName].
  Future<int> getChannelIndex(String channelName) async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<int>(
      DeviceMethods.getChannelIndexByName,
      {NeiryArgs.serial: serial, NeiryArgs.channelName: channelName},
    );
    return result!;
  }

  /// Returns the name of the channel at zero-based [index].
  Future<String> getChannelName(int index) async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<String>(
      DeviceMethods.getChannelNameByIndex,
      {NeiryArgs.serial: serial, NeiryArgs.index: index},
    );
    return result!;
  }

  /// Returns the total number of EEG channels on this device.
  Future<int> getChannelsCount() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<int>(
      DeviceMethods.getChannelsCount,
      {NeiryArgs.serial: serial},
    );
    return result!;
  }

  /// Returns the firmware version string of the device.
  Future<String> getFirmwareVersion() async {
    _checkNotDisposed();
    _checkConnected();
    final result = await _channel.invokeMethod<String>(
      DeviceMethods.getFirmwareVersion,
      {NeiryArgs.serial: serial},
    );
    return result!;
  }
}
