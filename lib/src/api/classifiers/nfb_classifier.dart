import 'dart:async';

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/nfb_user_state.dart';
import '../../models/individual_nfb_data.dart';

/// Wraps the native `clCNFB` lifecycle and exposes NFB brain-wave classifier
/// outputs as typed streams.
///
/// ## Usage
///
/// ```dart
/// final classifier = NfbClassifier(device);
/// classifier.stateStream.listen((state) { /* handle NfbUserState */ });
///
/// // With individual calibration data:
/// final calibrated = NfbClassifier(device, calibration: myCalibrationData);
///
/// // Release when done:
/// await classifier.dispose();
/// ```
///
/// ## Lifecycle
///
/// The factory constructor verifies that [device] is connected before
/// allocating the native handle. The classifier lives for the full connection
/// lifetime — from `Device.connect()` to `Device.disconnect()`. The native
/// `create` call is fired asynchronously — accessing [stateStream] or
/// [errorStream] before native creation completes is safe; events will start
/// flowing once the native side is ready (FIFO guarantee on the platform
/// thread).
///
/// Call [dispose] when finished to release the native C handle.
class NfbClassifier {
  /// Creates an [NfbClassifier] for the given [device].
  ///
  /// Pass [calibration] to initialize the classifier with individual NFB
  /// calibration data produced by [NfbCalibrator].
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory NfbClassifier(Device device, {IndividualNfbData? calibration}) {
    if (!device.isConnected) {
      throw StateError('Cannot create NfbClassifier before Device.connect()');
    }
    return NfbClassifier._(device.serial, calibration: calibration);
  }

  NfbClassifier._(String serial, {IndividualNfbData? calibration})
      : _serial = serial {
    if (calibration != null) {
      _nativeReady = _channel
          .invokeMethod<void>(ClassifierMethods.createCalibrated, {
            NeiryArgs.serial: _serial,
            NeiryArgs.calibrationData: calibration.toMap(),
          })
          .catchError((Object error) {
            _createError = error;
          });
    } else {
      _nativeReady = _channel
          .invokeMethod<void>(ClassifierMethods.create, {
            NeiryArgs.serial: _serial,
          })
          .catchError((Object error) {
            _createError = error;
          });
    }
  }

  // ── Channel ────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel(NeiryChannels.nfb);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<NfbUserState> _stateStream = _eventStream(
    const EventChannel(NeiryEvents.nfbState),
    NfbUserState.fromMap,
  );

  late final Stream<String> _errorStream = _eventStream(
    const EventChannel(NeiryEvents.nfbError),
    (map) => map['message'] as String,
  );

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NfbClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('NfbClassifier creation failed: $_createError');
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Stream<T> _eventStream<T>(
    EventChannel channel,
    T Function(Map<Object?, Object?>) decode,
  ) {
    return channel
        .receiveBroadcastStream({NeiryArgs.serial: _serial})
        .map((raw) => decode(raw as Map<Object?, Object?>));
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Emits per-sample NFB band power values from the native classifier.
  Stream<NfbUserState> get stateStream {
    _checkNotDisposed();
    _checkReady();
    return _stateStream;
  }

  /// Emits error messages forwarded from the native NFB classifier.
  Stream<String> get errorStream {
    _checkNotDisposed();
    _checkReady();
    return _errorStream;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native `clCNFB` handle.
  ///
  /// Idempotent — subsequent calls return immediately. After [dispose], all
  /// stream getters throw [StateError].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _nativeReady;
    if (_createError != null) {
      // Native handle was never created — nothing to destroy.
      return;
    }
    await _channel.invokeMethod<void>(
      ClassifierMethods.dispose,
      {NeiryArgs.serial: _serial},
    );
  }
}
