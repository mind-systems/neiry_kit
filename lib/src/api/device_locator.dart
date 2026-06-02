import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

import '../channel/channel_names.dart';
import '../channel/enums.dart';
import '../models/device_info.dart';
import 'device.dart';

/// Wraps the native `clCDeviceLocator` lifecycle — create, scan, create device,
/// threading control, and dispose.
///
/// ## Singleton semantics
///
/// Only one locator can exist at a time (the C API has the same constraint).
/// `DeviceLocator()` returns the existing instance when already created.
/// After [dispose], the next `DeviceLocator()` call creates a fresh instance.
///
/// ## Usage
///
/// ```dart
/// final locator = DeviceLocator();
///
/// // Discover devices for 10 seconds, filtering for headbands only.
/// locator.requestDevices(type: NeiryDeviceType.headband, searchTime: 10)
///   .listen((devices) { /* handle list */ });
///
/// // Create a device handle by serial.
/// await locator.createDevice('ABC123');
///
/// // Release when done.
/// await locator.dispose();
/// ```
class DeviceLocator {
  DeviceLocator._({String? logDirectory}) {
    final args =
        logDirectory != null ? {NeiryArgs.logDirectory: logDirectory} : null;
    _nativeReady = _channel
        .invokeMethod<void>(DeviceLocatorMethods.create, args)
        .catchError((Object error) {
      // Native create failed — store the error and null the singleton so the
      // next DeviceLocator() call retries rather than returning a broken
      // instance. Don't re-throw: _nativeReady completes normally so there is
      // no risk of an unhandled Future error if no method is awaited promptly.
      _createError = error;
      _instance = null;
    });
  }

  // ── Singleton ──────────────────────────────────────────────────────────────

  static DeviceLocator? _instance;

  /// Returns the existing locator instance or creates a new one.
  ///
  /// Pass [logDirectory] only on first creation — it is ignored once the
  /// native locator exists.
  factory DeviceLocator({String? logDirectory}) {
    _instance ??= DeviceLocator._(logDirectory: logDirectory);
    return _instance!;
  }

  // ── Channels ───────────────────────────────────────────────────────────────

  static const _channel = MethodChannel(NeiryChannels.deviceLocator);

  // Cached to avoid re-instantiation on every requestDevices call.
  static const _deviceListEventChannel = EventChannel(NeiryEvents.deviceList);

  // ── State ──────────────────────────────────────────────────────────────────

  /// Completes (without error) once the native create call finishes, whether
  /// it succeeded or failed. Check [_createError] afterwards.
  late Future<void> _nativeReady;

  /// Non-null when the native create call failed. Methods awaiting the native
  /// handle throw [StateError] when this is set.
  Object? _createError;

  bool _disposed = false;
  StreamSubscription<dynamic>? _scanSubscription;

  // ── Private helpers ────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('DeviceLocator has been disposed');
  }

  void _checkReady() {
    if (_createError != null) {
      throw StateError('DeviceLocator creation failed: $_createError');
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Scans for Neiry devices and emits a single list once the scan completes.
  ///
  /// The stream emits one `List<DeviceInfo>` (possibly empty) and then closes —
  /// this matches the native SDK behavior where `SetOnDeviceListEvent` fires
  /// once per `RequestDevices` call.
  ///
  /// Calling [requestDevices] while a previous scan is still running cancels
  /// the previous one before starting the new scan (cancel-on-overlap).
  ///
  /// ### FIFO ordering guarantee
  ///
  /// This method does NOT await `_nativeReady` before opening the event stream.
  /// That is intentional: Flutter's binary messenger dispatches platform
  /// channel messages on a FIFO queue on the platform thread. The `create`
  /// MethodChannel call was sent during construction — before this
  /// `receiveBroadcastStream` onListen message — so by the time the native
  /// `StreamHandler.onListen` fires, the native locator handle already exists.
  Stream<List<DeviceInfo>> requestDevices({
    NeiryDeviceType type = NeiryDeviceType.any,
    int searchTime = 5,
  }) {
    _checkNotDisposed();

    // Cancel any in-progress scan before starting a new one.
    _scanSubscription?.cancel();
    _scanSubscription = null;

    final controller = StreamController<List<DeviceInfo>>();

    final rawStream = _deviceListEventChannel.receiveBroadcastStream({
      NeiryArgs.deviceType: type.code,
      NeiryArgs.searchTime: searchTime,
    });

    // Captured synchronously so cancel-on-overlap and cancel-in-dispose can
    // identify this particular scan subscription.
    late final StreamSubscription<dynamic> thisSub;

    void clearIfCurrent() {
      if (identical(_scanSubscription, thisSub)) _scanSubscription = null;
    }

    thisSub = rawStream.listen(
      (dynamic raw) {
        if (!controller.isClosed) {
          final list = (raw as List)
              .map((e) => DeviceInfo.fromMap(e as Map<Object?, Object?>))
              .toList();
          controller.add(list);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      },
      onDone: () {
        clearIfCurrent();
        if (!controller.isClosed) controller.close();
      },
    );

    _scanSubscription = thisSub;

    controller.onCancel = () {
      clearIfCurrent();
      thisSub.cancel();
    };

    return controller.stream;
  }

  /// Creates and returns a [Device] for the given [serial].
  ///
  /// Tells the native side to allocate the device handle, then wraps it in a
  /// [Device] instance that exposes the full lifecycle and streaming API.
  Future<Device> createDevice(String serial) async {
    log('DeviceLocator.createDevice($serial) — disposed: $_disposed createError: $_createError', name: 'neiry_kit');
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    try {
      await _channel.invokeMethod<void>(
        DeviceLocatorMethods.createDevice,
        {NeiryArgs.serial: serial},
      );
    } catch (e) {
      log('DeviceLocator.createDevice($serial) error: $e', name: 'neiry_kit');
      rethrow;
    }
    log('DeviceLocator.createDevice($serial) done', name: 'neiry_kit');
    return Device(serial: serial);
  }

  /// Controls whether SDK callbacks fire on a background thread (default) or
  /// on the calling thread pumped by [update].
  ///
  /// Call with `true` before starting a scan when you want single-threaded
  /// mode; call [update] each frame to pump callbacks.
  Future<void> setSingleThreaded(bool enabled) async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(
      DeviceLocatorMethods.setSingleThreaded,
      {NeiryArgs.enabled: enabled},
    );
  }

  /// Pumps the SDK event loop when running in single-threaded mode.
  ///
  /// This is a no-op in multi-threaded mode (the C SDK ignores it).
  /// Must be called after [setSingleThreaded]`(true)` to receive callbacks.
  Future<void> update() async {
    _checkNotDisposed();
    await _nativeReady;
    _checkReady();
    await _channel.invokeMethod<void>(DeviceLocatorMethods.update);
  }

  /// Cancels any active scan, destroys the native locator handle, and
  /// releases the singleton so a new `DeviceLocator()` can be created.
  ///
  /// Awaiting this future ensures the native `destroy` call completes before
  /// returning, eliminating the race where a new `create` could arrive before
  /// the old `destroy` finishes.
  Future<void> dispose() async {
    _checkNotDisposed();
    _disposed = true;

    // Cancel any in-progress scan before tearing down the native side.
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    // Wait for native create to finish (or fail) before dispatching destroy.
    // _nativeReady always completes normally — check _createError to know
    // whether the native locator was actually created.
    await _nativeReady;
    if (_createError != null) {
      // Native locator was never created — nothing to destroy.
      _instance = null;
      return;
    }

    await _channel.invokeMethod<void>(DeviceLocatorMethods.dispose);

    // Allow a fresh DeviceLocator() to be created after this point.
    _instance = null;
  }
}
