import 'dart:async';

import 'package:flutter/services.dart';

import '../channel/channel_names.dart';
import '../models/calibration_event.dart';
import '../models/individual_nfb_data.dart';

/// Wraps the native `clCNFBCalibrator` — exposes full 4-stage calibration as a
/// [Stream<CalibrationEvent>], quick single-stage calibration as a
/// [Future<IndividualNfbData>], and stop/import/query methods for controlling
/// and persisting calibration data across sessions.
///
/// All methods are static; this class cannot be instantiated.
///
/// ## Usage
///
/// ```dart
/// // Full 4-stage calibration:
/// final sub = NfbCalibrator.calibrateIndividual().listen((event) {
///   switch (event) {
///     case CalibrationStageFinished(:final stage):
///       print('Stage $stage finished');
///     case CalibrationCompleted(:final data):
///       print('Calibrated: ${data.individualFrequency} Hz');
///   }
/// });
///
/// // Quick single-stage calibration:
/// final data = await NfbCalibrator.calibrateIndividualQuick();
///
/// // Persist and restore calibration between sessions:
/// await NfbCalibrator.importCalibrationData(data);
/// final stored = await NfbCalibrator.getCalibrationData();
/// final ready = await NfbCalibrator.isCalibrated();
/// ```
abstract final class NfbCalibrator {
  static const _channel = MethodChannel(NeiryChannels.nfbCalibrator);
  static const _calibrationEventChannel =
      EventChannel(NeiryEvents.nfbCalibration);

  /// Active raw EventChannel subscription — at most one runs at a time.
  static StreamSubscription<dynamic>? _calibrationSubscription;

  /// Pending Completer for an active [calibrateIndividualQuick] call.
  /// Tracked so it can be failed immediately on external cancellation,
  /// preventing the returned Future from hanging indefinitely.
  static Completer<IndividualNfbData>? _quickCompleter;

  /// Active StreamController for an in-progress [calibrateIndividual] call.
  /// Tracked so it can be closed immediately on external cancellation,
  /// unblocking any consumer doing `await for`.
  static StreamController<CalibrationEvent>? _calibrationController;

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Cancels any active calibration subscription and immediately closes/fails
  /// any pending consumer so it does not hang after an overlap or explicit stop.
  ///
  /// Does NOT invoke the native `stopCalibration` — the caller is responsible
  /// for that to keep the semantics clear (fire-and-forget vs awaited).
  static void _cancelActiveCalibration() {
    _calibrationSubscription?.cancel();
    _calibrationSubscription = null;

    if (_calibrationController != null &&
        !_calibrationController!.isClosed) {
      _calibrationController!.close();
    }
    _calibrationController = null;

    if (_quickCompleter != null && !_quickCompleter!.isCompleted) {
      _quickCompleter!.completeError(StateError('Calibration cancelled'));
    }
    _quickCompleter = null;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Starts a full 4-stage individual NFB calibration.
  ///
  /// Emits up to four [CalibrationStageFinished] events (one per stage) followed
  /// by a single [CalibrationCompleted] event carrying the produced
  /// [IndividualNfbData], then the stream closes. The stream also closes with
  /// an error if the native side aborts (e.g. device disconnect mid-run).
  ///
  /// Calling [calibrateIndividual] or [calibrateIndividualQuick] while a
  /// calibration is already running cancels the previous one before starting
  /// the new one (cancel-on-overlap). The native `clCNFBCalibrator` is
  /// device-scoped implicitly — no serial is required.
  ///
  /// Cancel the returned stream subscription to stop calibration early:
  /// `subscription.cancel()` stops both the Dart stream and the native
  /// calibrator.
  static Stream<CalibrationEvent> calibrateIndividual() {
    _cancelActiveCalibration();
    _channel
        .invokeMethod<void>(NFBCalibratorMethods.stopCalibration)
        .catchError((_) {});

    final controller = StreamController<CalibrationEvent>();
    _calibrationController = controller;

    // Open the EventChannel FIRST so no early events are missed before the
    // startCalibration MethodChannel call is processed on the platform thread.
    final rawStream = _calibrationEventChannel.receiveBroadcastStream();

    late final StreamSubscription<dynamic> thisSub;

    void clearIfCurrent() {
      if (identical(_calibrationSubscription, thisSub)) {
        _calibrationSubscription = null;
      }
      if (identical(_calibrationController, controller)) {
        _calibrationController = null;
      }
    }

    thisSub = rawStream.listen(
      (dynamic raw) {
        if (!controller.isClosed) {
          controller.add(
            CalibrationEvent.deserialize(raw as Map<Object?, Object?>),
          );
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

    _calibrationSubscription = thisSub;

    // THEN invoke startCalibration. Chaining catchError surfaces a failed start
    // call (e.g. no device connected) as a stream error rather than leaving
    // an unhandled Future rejection.
    _channel
        .invokeMethod<void>(NFBCalibratorMethods.startCalibration)
        .catchError((Object error, StackTrace stack) {
      if (!controller.isClosed) {
        controller.addError(error, stack);
        controller.close();
      }
    });

    controller.onCancel = () {
      // Only invoke native stop when this subscription is still the active one.
      // If a newer calibration has already started, invoking stop here would
      // kill it — the new calibration clears _calibrationSubscription before
      // this onCancel can fire a stale stop.
      final wasCurrent = identical(_calibrationSubscription, thisSub);
      clearIfCurrent();
      thisSub.cancel();
      if (wasCurrent) {
        _channel
            .invokeMethod<void>(NFBCalibratorMethods.stopCalibration)
            .catchError((_) {});
      }
    };

    return controller.stream;
  }

  /// Starts a quick single-stage individual NFB calibration.
  ///
  /// Resolves to the produced [IndividualNfbData] once the native side emits
  /// [CalibrationCompleted]. Any active calibration (full or quick) is
  /// cancelled before starting.
  ///
  /// Throws if the device is not connected, if [stopCalibration] is called
  /// while waiting, or if the native stream ends before emitting a
  /// [CalibrationCompleted] event (e.g. device disconnects mid-run).
  ///
  /// **Note for native bridge implementers:** the `startCalibration` handler
  /// must check for `NeiryArgs.calibratorData == 'quick'` to route to
  /// `CalibrateIndividualNFBQuick()` rather than `CalibrateIndividualNFB()`.
  static Future<IndividualNfbData> calibrateIndividualQuick() {
    _cancelActiveCalibration();
    _channel
        .invokeMethod<void>(NFBCalibratorMethods.stopCalibration)
        .catchError((_) {});

    final completer = Completer<IndividualNfbData>();
    _quickCompleter = completer;

    // Open the EventChannel FIRST to avoid losing the completion event.
    final rawStream = _calibrationEventChannel.receiveBroadcastStream();

    late final StreamSubscription<dynamic> thisSub;

    void clearIfCurrent() {
      if (identical(_calibrationSubscription, thisSub)) {
        _calibrationSubscription = null;
      }
      if (identical(_quickCompleter, completer)) {
        _quickCompleter = null;
      }
    }

    thisSub = rawStream.listen(
      (dynamic raw) {
        final event =
            CalibrationEvent.deserialize(raw as Map<Object?, Object?>);
        if (event is CalibrationCompleted) {
          clearIfCurrent();
          thisSub.cancel();
          if (!completer.isCompleted) completer.complete(event.data);
        }
        // CalibrationStageFinished is unexpected in quick mode — ignored.
      },
      onError: (Object error, StackTrace stack) {
        clearIfCurrent();
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        // The native side ended the EventChannel stream without emitting
        // CalibrationCompleted (e.g. device disconnect). Fail the Future so
        // the caller's await does not hang indefinitely.
        clearIfCurrent();
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Calibration stream ended without producing data'),
          );
        }
      },
    );

    _calibrationSubscription = thisSub;

    // THEN invoke startCalibration in quick mode. Chaining catchError surfaces
    // a failed start call as a Future error rather than an unhandled rejection.
    _channel
        .invokeMethod<void>(
          NFBCalibratorMethods.startCalibration,
          {NeiryArgs.calibratorData: 'quick'},
        )
        .catchError((Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    });

    return completer.future;
  }

  /// Stops any in-progress calibration (full or quick).
  ///
  /// Cancels the active Dart subscription, closes any open stream, and fails
  /// any pending quick-calibration Future so it does not hang. Then tells the
  /// native `clCNFBCalibrator` to abort. Safe to call when no calibration is
  /// running.
  static Future<void> stopCalibration() async {
    _cancelActiveCalibration();
    await _channel.invokeMethod<void>(NFBCalibratorMethods.stopCalibration);
  }

  /// Imports previously obtained [IndividualNfbData] into the native calibrator.
  ///
  /// Use this to restore calibration data from a previous session so classifiers
  /// can be initialized without running a new calibration.
  static Future<void> importCalibrationData(IndividualNfbData data) async {
    await _channel.invokeMethod<void>(
      NFBCalibratorMethods.importCalibration,
      {NeiryArgs.calibratorData: data.toMap()},
    );
  }

  /// Returns the calibration data stored in the native calibrator, or `null`
  /// if no calibration has been performed or imported yet.
  static Future<IndividualNfbData?> getCalibrationData() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      NFBCalibratorMethods.getCalibration,
    );
    return result != null ? IndividualNfbData.fromMap(result) : null;
  }

  /// Returns `true` when valid calibration data is present in the native
  /// calibrator (either produced by a completed run or imported via
  /// [importCalibrationData]).
  static Future<bool> isCalibrated() async {
    final result = await _channel.invokeMethod<bool>(
      NFBCalibratorMethods.isCalibrated,
    );
    return result ?? false;
  }
}
