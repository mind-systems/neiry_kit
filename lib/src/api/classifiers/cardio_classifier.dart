import 'dart:async';

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/cardio_data.dart';
import '../../models/ppg_data.dart';
import '../../models/individual_nfb_data.dart';

/// Wraps the native `clCCardio` lifecycle and exposes Cardio classifier
/// outputs as typed streams.
///
/// ## Usage
///
/// ```dart
/// // Plain creation (no individual NFB calibration):
/// final classifier = CardioClassifier(device);
///
/// // With individual NFB calibration data:
/// final classifier = CardioClassifier.withCalibration(device, nfbData);
///
/// // Listen for Cardio metrics (only valid when metricsAvailable is true):
/// classifier.stateStream.listen((data) {
///   if (data.metricsAvailable) {
///     print('HR: ${data.heartRate}, stress: ${data.stressIndex}');
///   }
/// });
///
/// // Listen for raw PPG waveform batches:
/// classifier.ppgStream.listen((ppg) { /* handle PpgData */ });
///
/// // Know when internal calibration completes and valid metrics begin:
/// classifier.calibratedStream.listen((_) { /* calibration done */ });
///
/// // Release when done:
/// await classifier.dispose();
/// ```
///
/// ## Lifecycle
///
/// Both factory constructors verify that EEG streaming is active on [device]
/// before allocating the native handle. The native `create` call is fired
/// asynchronously — accessing streams before native creation completes is safe;
/// events will start flowing once the native side is ready.
///
/// Unlike other classifiers, the Cardio C API does not expose a
/// `SetOnErrorEvent` callback. Errors surface as [PlatformException] thrown
/// directly from stream subscriptions or method calls.
///
/// Call [dispose] when finished to release the native C handle.
class CardioClassifier {
  /// Creates a [CardioClassifier] for the given [device].
  ///
  /// Throws [StateError] when [device] has not been started yet.
  factory CardioClassifier(Device device) {
    if (!device.isStarted) {
      throw StateError(
        'Cannot create CardioClassifier before Device.start()',
      );
    }
    return CardioClassifier._(device.serial, calibration: null);
  }

  /// Creates a [CardioClassifier] with individual NFB calibration data.
  ///
  /// Pass [nfbData] produced by [NfbCalibrator] to initialize the native
  /// classifier with per-user NFB parameters for improved accuracy.
  ///
  /// Throws [StateError] when [device] has not been started yet.
  factory CardioClassifier.withCalibration(
    Device device,
    IndividualNfbData nfbData,
  ) {
    if (!device.isStarted) {
      throw StateError(
        'Cannot create CardioClassifier before Device.start()',
      );
    }
    return CardioClassifier._(device.serial, calibration: nfbData);
  }

  CardioClassifier._(String serial, {IndividualNfbData? calibration})
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

  static const _channel = MethodChannel(NeiryChannels.cardio);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<CardioData> _stateStream = _eventStream(
    const EventChannel(NeiryEvents.cardioData),
    CardioData.fromMap,
  );

  late final Stream<PpgData> _ppgStream = _eventStream(
    const EventChannel(NeiryEvents.ppgData),
    PpgData.fromMap,
  );

  /// Emits once when the Cardio classifier's internal calibration completes
  /// (native `clCCardio_SetOnCalibratedEvent`). After this event, float metric
  /// fields in [CardioData] become valid ([CardioData.metricsAvailable] is
  /// `true`).
  late final Stream<void> _calibratedStream = const EventChannel(
    NeiryEvents.cardioCalibratedEvent,
  ).receiveBroadcastStream({NeiryArgs.serial: _serial}).map((_) {});

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('CardioClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('CardioClassifier creation failed: $_createError');
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

  /// Emits per-sample [CardioData] values from the native Cardio classifier.
  ///
  /// Float metric fields ([CardioData.heartRate], [CardioData.stressIndex],
  /// [CardioData.kaplanIndex]) are only valid when
  /// [CardioData.metricsAvailable] is `true`.
  Stream<CardioData> get stateStream {
    _checkNotDisposed();
    _checkReady();
    return _stateStream;
  }

  /// Emits raw PPG waveform batches from the device.
  Stream<PpgData> get ppgStream {
    _checkNotDisposed();
    _checkReady();
    return _ppgStream;
  }

  /// Emits once when the Cardio classifier's internal calibration completes.
  ///
  /// After this event, [CardioData.metricsAvailable] transitions to `true` and
  /// the float metric fields carry valid values.
  Stream<void> get calibratedStream {
    _checkNotDisposed();
    _checkReady();
    return _calibratedStream;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native `clCCardio` handle.
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
