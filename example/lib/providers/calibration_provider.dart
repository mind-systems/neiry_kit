import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'calibration_file_manager.dart';
import 'calibration_timer_provider.dart';
import 'device_state_providers.dart';
import 'nfb_calibration_provider.dart';

/// Manages the full NFB calibration lifecycle — full 4-stage, quick, abort,
/// import, and export — and persists results to the shared
/// [nfbCalibrationProvider].
class CalibrationNotifier extends AsyncNotifier<IndividualNfbData?> {
  StreamSubscription<CalibrationEvent>? _sub;
  Completer<IndividualNfbData>? _fullCompleter;

  /// Set by [abort] before it completes [_fullCompleter] with an error.
  /// Guards [startFull] from overwriting the state that [abort] already set.
  bool _aborted = false;

  /// `true` while [abort] is driving the `loading → error → data` state
  /// sequence. Listeners should skip cues when this is `true`.
  bool get isAborting => _aborted;

  /// `true` from the moment [startFull] or [startQuick] is called until the
  /// terminal state assignment completes (including error). Cleared on a
  /// microtask after `state = await AsyncValue.guard(...)` so that `ref.listen`
  /// callbacks observing the `loading → data` / `loading → error` transitions
  /// still see `isRunning == true` and can fire audio cues. [importFromFile]
  /// and the cold-open [build] path intentionally do not set this flag so their
  /// `loading → data` transitions are silent.
  bool _running = false;

  /// Whether a user-initiated calibration run is currently in progress.
  bool get isRunning => _running;

  @override
  Future<IndividualNfbData?> build() async {
    ref.onDispose(() {
      _sub?.cancel();
      _fullCompleter = null;
    });
    // Reset the on-screen calibration state when the device disconnects so the UI
    // does not keep showing the previous session's "calibrated" result. Pairs with
    // the native locator-session reset that makes the SDK forget the old calibration.
    // Do NOT clear nfbCalibrationProvider — that holds the portable IndividualNfbData
    // the "Use NFB Calibration" toggles apply on the next connect.
    ref.listen(deviceConnectionStateProvider, (prev, next) {
      if (next.whenOrNull(data: (s) => s) == NeiryConnectionState.disconnected) {
        state = const AsyncValue.data(null);
      }
    });
    return NfbCalibrator.getCalibrationData();
  }

  // ── Full 4-stage calibration ────────────────────────────────────────────────

  Future<void> startFull() async {
    _aborted = false;
    _running = true;
    await WakelockPlus.enable();
    state = const AsyncValue.loading();
    _fullCompleter = Completer<IndividualNfbData>();

    final timer = ref.read(calibrationTimerProvider.notifier);
    timer.startStage(CalibrationStage.stage1);

    _sub = NfbCalibrator.calibrateIndividual().listen(
      (event) {
        switch (event) {
          case CalibrationStageFinished(:final stage):
            if (stage.code < 3) {
              timer.startStage(CalibrationStage.fromCode(stage.code + 1));
            }
          case CalibrationCompleted(:final data):
            timer.stop();
            if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
              _fullCompleter!.complete(data);
            }
            _sub?.cancel();
            _sub = null;
        }
      },
      onError: (Object error, StackTrace stack) {
        timer.stop();
        if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
          _fullCompleter!.completeError(error, stack);
        }
        _sub?.cancel();
        _sub = null;
      },
    );

    state = await AsyncValue.guard(() async {
      try {
        return await _fullCompleter!.future;
      } finally {
        await WakelockPlus.disable();
      }
    });
    Future.microtask(() => _running = false);

    if (_aborted) return; // abort() already wrote the correct state
    _writeToSharedProvider();
  }

  // ── Quick single-stage calibration ─────────────────────────────────────────

  Future<void> startQuick() async {
    _running = true;
    await WakelockPlus.enable();
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      try {
        return await NfbCalibrator.calibrateIndividualQuick();
      } finally {
        await WakelockPlus.disable();
      }
    });
    Future.microtask(() => _running = false);

    _writeToSharedProvider();
  }

  // ── Abort ───────────────────────────────────────────────────────────────────

  Future<void> abort() async {
    if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
      _aborted = true;
      _fullCompleter!.completeError(StateError('Calibration aborted'));
    }
    _sub?.cancel();
    _sub = null;
    _fullCompleter = null;
    ref.read(calibrationTimerProvider.notifier).stop();
    await WakelockPlus.disable();
    state = AsyncValue.data(await NfbCalibrator.getCalibrationData());
    // Clear the flag after all state assignments so that ref.listen callbacks
    // observing those transitions still see isAborting == true.
    Future.microtask(() => _aborted = false);
  }

  // ── File I/O ────────────────────────────────────────────────────────────────

  /// Opens a file picker and imports calibration data from the chosen JSON.
  ///
  /// No-op when the user cancels. Updates both [calibrationProvider] and
  /// [nfbCalibrationProvider] on success.
  Future<void> importFromFile() async {
    try {
      final data = await CalibrationFileManager.importFromFile();
      if (data == null) return;
      await NfbCalibrator.importCalibrationData(data);
      state = AsyncValue.data(data);
      ref.read(nfbCalibrationProvider.notifier).state = data;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Writes the current calibration data to a JSON file in the app documents
  /// directory.
  ///
  /// Returns the written [File], or `null` when no calibration data is present.
  Future<File?> exportToFile() async {
    final value = state.value;
    if (value == null) return null;
    return CalibrationFileManager.exportToFile(value);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _writeToSharedProvider() {
    if (state.hasValue && state.value != null) {
      ref.read(nfbCalibrationProvider.notifier).state = state.value;
    }
  }
}

final calibrationProvider =
    AsyncNotifierProvider<CalibrationNotifier, IndividualNfbData?>(
  CalibrationNotifier.new,
);
