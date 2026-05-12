import 'dart:async';

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/mems_data.dart';
import '../../models/individual_nfb_data.dart';

/// Wraps the native MEMS classifier lifecycle and exposes motion sensor
/// batches as a typed stream.
///
/// ## Usage
///
/// ```dart
/// // Plain creation (no individual NFB calibration):
/// final classifier = MEMSClassifier(device);
///
/// // With individual NFB calibration data:
/// final classifier = MEMSClassifier.withCalibration(device, nfbData);
///
/// // Listen for MEMS sample batches:
/// classifier.memsStream.listen((samples) {
///   for (final s in samples) {
///     print('accel: ${s.accelerometer}, gyro: ${s.gyroscope}');
///   }
/// });
///
/// // Release when done:
/// await classifier.dispose();
/// ```
///
/// ## Lifecycle
///
/// Both factory constructors verify that [device] is connected before
/// allocating the native handle. The classifier lives for the full connection
/// lifetime — from `Device.connect()` to `Device.disconnect()`. The native
/// `create` call is fired asynchronously — accessing the stream before native
/// creation completes is safe; events will start flowing once the native side
/// is ready.
///
/// Call [dispose] when finished to release the native C handle.
class MEMSClassifier {
  /// Creates a [MEMSClassifier] for the given [device].
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory MEMSClassifier(Device device) {
    if (!device.isConnected) {
      throw StateError(
        'Cannot create MEMSClassifier before Device.connect()',
      );
    }
    return MEMSClassifier._(device.serial, calibration: null);
  }

  /// Creates a [MEMSClassifier] with individual NFB calibration data.
  ///
  /// Pass [data] produced by [NfbCalibrator] to initialize the native
  /// classifier with per-user NFB parameters for improved accuracy.
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory MEMSClassifier.withCalibration(
    Device device,
    IndividualNfbData data,
  ) {
    if (!device.isConnected) {
      throw StateError(
        'Cannot create MEMSClassifier before Device.connect()',
      );
    }
    return MEMSClassifier._(device.serial, calibration: data);
  }

  MEMSClassifier._(String serial, {IndividualNfbData? calibration})
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

  static const _channel = MethodChannel(NeiryChannels.mems);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<List<MemsSample>> _memsStream = const EventChannel(
    NeiryEvents.memsData,
  ).receiveBroadcastStream({NeiryArgs.serial: _serial}).map((raw) {
    return (raw as List)
        .map((e) => MemsSample.fromMap(e as Map<Object?, Object?>))
        .toList();
  });

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('MEMSClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('MEMSClassifier creation failed: $_createError');
    }
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Emits batches of [MemsSample] values from the native MEMS classifier.
  ///
  /// Each event contains all samples accumulated since the previous callback
  /// (mirrors `clCMEMSTimedData`). All fields are always valid — MEMS data
  /// carries no sentinel values.
  Stream<List<MemsSample>> get memsStream {
    _checkNotDisposed();
    _checkReady();
    return _memsStream;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native MEMS handle.
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
