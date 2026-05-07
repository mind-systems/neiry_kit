import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'calibration_file_manager.dart';
import 'calibration_timer_provider.dart';
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

  @override
  Future<IndividualNfbData?> build() async {
    ref.onDispose(() {
      _sub?.cancel();
      _fullCompleter = null;
    });
    return NfbCalibrator.getCalibrationData();
  }

  // ── Full 4-stage calibration ────────────────────────────────────────────────

  Future<void> startFull() async {
    _aborted = false;
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
        }
      },
      onError: (Object error, StackTrace stack) {
        timer.stop();
        if (_fullCompleter != null && !_fullCompleter!.isCompleted) {
          _fullCompleter!.completeError(error, stack);
        }
      },
    );

    state = await AsyncValue.guard(() async {
      try {
        return await _fullCompleter!.future;
      } finally {
        await WakelockPlus.disable();
      }
    });

    if (_aborted) return; // abort() already wrote the correct state
    _writeToSharedProvider();
  }

  // ── Quick single-stage calibration ─────────────────────────────────────────

  Future<void> startQuick() async {
    await WakelockPlus.enable();
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      try {
        return await NfbCalibrator.calibrateIndividualQuick();
      } finally {
        await WakelockPlus.disable();
      }
    });

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
