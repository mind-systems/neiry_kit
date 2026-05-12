import 'dart:async';

import 'package:flutter/services.dart';

import '../device.dart';
import '../../channel/channel_names.dart';
import '../../models/emotions_states.dart';

/// Wraps the native `clCEmotions` lifecycle and exposes emotions classifier
/// outputs as typed streams.
///
/// ## Usage
///
/// ```dart
/// final classifier = EmotionsClassifier(device);
/// classifier.stateStream.listen((state) { /* handle EmotionsStates */ });
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
class EmotionsClassifier {
  /// Creates an [EmotionsClassifier] for the given [device].
  ///
  /// Throws [StateError] when [device] has not been connected yet.
  factory EmotionsClassifier(Device device) {
    if (!device.isConnected) {
      throw StateError('Cannot create EmotionsClassifier before Device.connect()');
    }
    return EmotionsClassifier._(device.serial);
  }

  EmotionsClassifier._(String serial) : _serial = serial {
    _nativeReady = _channel
        .invokeMethod<void>(ClassifierMethods.create, {
          NeiryArgs.serial: _serial,
        })
        .catchError((Object error) {
          _createError = error;
        });
  }

  // ── Channel ────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel(NeiryChannels.emotions);

  // ── State ──────────────────────────────────────────────────────────────────

  final String _serial;

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late final Future<void> _nativeReady;

  /// Non-null when the native create call failed.
  Object? _createError;

  bool _disposed = false;

  // ── Cached streams ─────────────────────────────────────────────────────────

  late final Stream<EmotionsStates> _stateStream = _eventStream(
    const EventChannel(NeiryEvents.emotionsState),
    EmotionsStates.fromMap,
  );

  late final Stream<String> _errorStream = _eventStream(
    const EventChannel(NeiryEvents.emotionsError),
    (map) => map['message'] as String,
  );

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('EmotionsClassifier has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('EmotionsClassifier creation failed: $_createError');
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

  /// Emits per-sample emotions classifier output values from the native classifier.
  Stream<EmotionsStates> get stateStream {
    _checkNotDisposed();
    _checkReady();
    return _stateStream;
  }

  /// Emits error messages forwarded from the native emotions classifier.
  Stream<String> get errorStream {
    _checkNotDisposed();
    _checkReady();
    return _errorStream;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the native `clCEmotions` handle.
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
