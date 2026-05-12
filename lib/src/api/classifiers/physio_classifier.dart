import 'dart:async';

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/physio_baselines.dart';
import '../../models/physio_states.dart';

/// Wraps the native `clCPhysiologicalStates` lifecycle and exposes physiological
/// state classifier outputs as typed streams.
///
/// ## Usage
///
/// ```dart
/// final classifier = PhysioClassifier(device);
/// classifier.stateStream.listen((state) { /* handle PhysiologicalStatesValue */ });
///
/// // Start baseline calibration to improve accuracy:
/// await classifier.startBaselineCalibration();
/// classifier.calibrationProgress.listen((p) { /* 0.0–1.0 */ });
/// classifier.calibrated.listen((baselines) { /* PhysiologicalStatesBaselines, save for later */ });
///
/// // Or import previously saved baselines:
/// await classifier.importBaselines(savedBaselines);
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
/// `create` call is fired asynchronously — accessing streams before native
/// creation completes is safe; events will start flowing once the native side
/// is ready.
///
/// Call [dispose] when finished to release the native C handle.
class PhysioClassifier {
  /// Creates a [PhysioClassifier] for the given [device].
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory PhysioClassifier(Device device) {
    if (!device.isConnected) {
      throw StateError('Cannot create PhysioClassifier before Device.connect()');
    }
    return PhysioClassifier._(device.serial);
  }

  PhysioClassifier._(String serial) : _serial = serial {
    _nativeReady = _channel
        .invokeMethod<void>(ClassifierMethods.create, {
          NeiryArgs.serial: _serial,
        })
        .catchError((Object error) {
          _createError = error;
        });
  }

  // ── Channel ────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel(NeiryChannels.physiological);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<PhysiologicalStatesValue> _stateStream = _eventStream(
    const EventChannel(NeiryEvents.physiologicalState),
    PhysiologicalStatesValue.fromMap,
  );

  late final Stream<double> _calibrationProgress = _eventStream(
    const EventChannel(NeiryEvents.physiologicalCalibrationProgress),
    (map) => (map['progress'] as num).toDouble(),
  );

  late final Stream<PhysiologicalStatesBaselines> _calibrated = _eventStream(
    const EventChannel(NeiryEvents.physiologicalCalibrated),
    PhysiologicalStatesBaselines.fromMap,
  );

  late final Stream<void> _individualNfbStream =
      const EventChannel(NeiryEvents.physiologicalIndividualNfb)
          .receiveBroadcastStream({NeiryArgs.serial: _serial})
          .map((_) {});

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PhysioClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('PhysioClassifier creation failed: $_createError');
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

  /// Emits per-sample physiological state values from the native classifier.
  Stream<PhysiologicalStatesValue> get stateStream {
    _checkNotDisposed();
    _checkReady();
    return _stateStream;
  }

  /// Emits calibration progress values in the range 0.0–1.0 during an active
  /// baseline calibration.
  Stream<double> get calibrationProgress {
    _checkNotDisposed();
    _checkReady();
    return _calibrationProgress;
  }

  /// Emits once when baseline calibration completes, carrying the structured
  /// baselines data (`PhysiologicalStatesBaselines`). Persist this data (e.g.
  /// via `toMap()` + JSON) and pass it to [importBaselines] on subsequent
  /// sessions to skip re-calibration.
  Stream<PhysiologicalStatesBaselines> get calibrated {
    _checkNotDisposed();
    _checkReady();
    return _calibrated;
  }

  /// Emits a notification whenever the physiological states classifier refreshes
  /// its internal NFB state. Carries no data — use it as a trigger only.
  Stream<void> get individualNfbStream {
    _checkNotDisposed();
    _checkReady();
    return _individualNfbStream;
  }

  // ── Methods ────────────────────────────────────────────────────────────────

  /// Starts baseline calibration on the native `clCPhysiologicalStates`
  /// classifier. Monitor progress via [calibrationProgress] and receive the
  /// completed baselines blob via [calibrated].
  Future<void> startBaselineCalibration() async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      ClassifierMethods.startBaselineCalibration,
      {NeiryArgs.serial: _serial},
    );
  }

  /// Imports previously saved [baselines] into the native classifier, allowing
  /// it to skip calibration and produce valid outputs immediately.
  Future<void> importBaselines(PhysiologicalStatesBaselines baselines) async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      ClassifierMethods.importBaselines,
      {NeiryArgs.serial: _serial, NeiryArgs.baselines: baselines.toMap()},
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native `clCPhysiologicalStates` handle.
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
