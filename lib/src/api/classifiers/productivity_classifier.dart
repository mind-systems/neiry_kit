import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/productivity_metrics.dart';
import '../../models/productivity_indexes.dart';
import '../../models/productivity_baselines.dart';
import '../../models/individual_nfb_data.dart';

/// Wraps the native `clCProductivity` lifecycle and exposes productivity
/// classifier outputs as typed streams.
///
/// ## Usage
///
/// ```dart
/// // Plain creation (no individual NFB calibration):
/// final classifier = ProductivityClassifier(device);
///
/// // With individual NFB calibration data:
/// final classifier = ProductivityClassifier.withCalibration(device, nfbData);
///
/// classifier.metricsStream.listen((m) { /* handle ProductivityMetrics */ });
/// classifier.indexesStream.listen((i) { /* handle ProductivityIndexes */ });
///
/// // Start baseline calibration to improve accuracy:
/// await classifier.startBaselineCalibration();
/// classifier.calibrationProgress.listen((p) { /* 0.0–1.0 */ });
/// classifier.calibrated.listen((baselines) { /* opaque blob, save for later */ });
///
/// // Or import previously saved baselines:
/// await classifier.importBaselines(savedBlob);
///
/// // Reset accumulated fatigue when needed:
/// await classifier.resetAccumulatedFatigue();
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
/// `create` call is fired asynchronously — accessing streams before native
/// creation completes is safe; events will start flowing once the native side
/// is ready.
///
/// Call [dispose] when finished to release the native C handle.
class ProductivityClassifier {
  /// Creates a [ProductivityClassifier] for the given [device].
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory ProductivityClassifier(Device device) {
    if (!device.isConnected) {
      throw StateError(
        'Cannot create ProductivityClassifier before Device.connect()',
      );
    }
    return ProductivityClassifier._(device.serial, calibration: null);
  }

  /// Creates a [ProductivityClassifier] with individual NFB calibration data.
  ///
  /// Pass [nfbData] produced by [NfbCalibrator] to initialize the native
  /// classifier with per-user NFB parameters for improved accuracy.
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  ///
  /// On Android, throws [UnsupportedError] — the Android Capsule AAR does not
  /// export `clCProductivity_CreateWithIndividualData`. Use the plain
  /// [ProductivityClassifier] factory instead.
  factory ProductivityClassifier.withCalibration(
    Device device,
    IndividualNfbData nfbData,
  ) {
    if (!device.isConnected) {
      throw StateError(
        'Cannot create ProductivityClassifier before Device.connect()',
      );
    }
    if (Platform.isAndroid) {
      throw UnsupportedError(
        'ProductivityClassifier.withCalibration is not supported on Android: '
        'clCProductivity_CreateWithIndividualData is not exported by the Capsule AAR. '
        'Use ProductivityClassifier(device) instead.',
      );
    }
    return ProductivityClassifier._(device.serial, calibration: nfbData);
  }

  ProductivityClassifier._(String serial, {IndividualNfbData? calibration})
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

  static const _channel = MethodChannel(NeiryChannels.productivity);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<ProductivityBaselines> _baselineStream = _eventStream(
    const EventChannel(NeiryEvents.productivityBaselines),
    ProductivityBaselines.fromMap,
  );

  late final Stream<ProductivityIndexes> _indexesStream = _eventStream(
    const EventChannel(NeiryEvents.productivityIndexes),
    ProductivityIndexes.fromMap,
  );

  late final Stream<ProductivityMetrics> _metricsStream = _eventStream(
    const EventChannel(NeiryEvents.productivityMetrics),
    ProductivityMetrics.fromMap,
  );

  late final Stream<double> _calibrationProgress = _eventStream(
    const EventChannel(NeiryEvents.productivityCalibrationProgress),
    (map) => (map['progress'] as num).toDouble(),
  );

  late final Stream<Uint8List> _calibrated = _eventStream(
    const EventChannel(NeiryEvents.productivityCalibrated),
    (map) => map['baselines'] as Uint8List,
  );

  late final Stream<void> _individualNfbStream =
      const EventChannel(NeiryEvents.productivityIndividualNfb)
          .receiveBroadcastStream({NeiryArgs.serial: _serial})
          .map((_) {});

  late final Stream<String> _errorStream = _eventStream(
    const EventChannel(NeiryEvents.productivityError),
    (map) => map['message'] as String,
  );

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('ProductivityClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError(
        'ProductivityClassifier creation failed: $_createError',
      );
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

  /// Emits [ProductivityBaselines] snapshots during baseline calibration.
  Stream<ProductivityBaselines> get baselineStream {
    _checkNotDisposed();
    _checkReady();
    return _baselineStream;
  }

  /// Emits per-sample [ProductivityIndexes] values from the native classifier.
  Stream<ProductivityIndexes> get indexesStream {
    _checkNotDisposed();
    _checkReady();
    return _indexesStream;
  }

  /// Emits per-sample [ProductivityMetrics] values from the native classifier.
  Stream<ProductivityMetrics> get metricsStream {
    _checkNotDisposed();
    _checkReady();
    return _metricsStream;
  }

  /// Emits calibration progress values in the range 0.0–1.0 during an active
  /// baseline calibration.
  Stream<double> get calibrationProgress {
    _checkNotDisposed();
    _checkReady();
    return _calibrationProgress;
  }

  /// Emits once when baseline calibration completes, carrying the opaque
  /// baselines blob. Persist this blob and pass it to [importBaselines] on
  /// subsequent sessions to skip re-calibration.
  Stream<Uint8List> get calibrated {
    _checkNotDisposed();
    _checkReady();
    return _calibrated;
  }

  /// Emits a notification whenever the productivity classifier refreshes its
  /// internal NFB state. Carries no data — use it as a trigger only.
  Stream<void> get individualNfbStream {
    _checkNotDisposed();
    _checkReady();
    return _individualNfbStream;
  }

  /// Emits error messages forwarded from the native productivity classifier.
  Stream<String> get errorStream {
    _checkNotDisposed();
    _checkReady();
    return _errorStream;
  }

  // ── Methods ────────────────────────────────────────────────────────────────

  /// Starts baseline calibration on the native `clCProductivity` classifier.
  /// Monitor progress via [calibrationProgress] and receive the completed
  /// baselines blob via [calibrated].
  Future<void> startBaselineCalibration() async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      ClassifierMethods.startBaselineCalibration,
      {NeiryArgs.serial: _serial},
    );
  }

  /// Imports previously saved [data] baselines into the native classifier,
  /// allowing it to skip calibration and produce valid outputs immediately.
  Future<void> importBaselines(Uint8List data) async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      ClassifierMethods.importBaselines,
      {NeiryArgs.serial: _serial, NeiryArgs.baselines: data},
    );
  }

  /// Resets accumulated fatigue state in the native `clCProductivity`
  /// classifier. Call this when the user takes a break and fatigue should
  /// be re-evaluated from zero.
  Future<void> resetAccumulatedFatigue() async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      ClassifierMethods.resetAccumulatedFatigue,
      {NeiryArgs.serial: _serial},
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native `clCProductivity` handle.
  ///
  /// Idempotent — subsequent calls return immediately. After [dispose], all
  /// stream getters and methods throw [StateError].
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
