import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

typedef CalibrationTimerState = ({int elapsed, CalibrationStage? stage});

/// Tracks elapsed seconds and active stage for the full 4-stage calibration.
///
/// Start a stage with [startStage]; call [stop] to reset. The timer is
/// automatically cancelled when the provider is disposed.
class CalibrationTimerNotifier extends Notifier<CalibrationTimerState> {
  Timer? _timer;

  @override
  CalibrationTimerState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return (elapsed: 0, stage: null);
  }

  /// Starts (or restarts) the 1-second tick for [stage].
  void startStage(CalibrationStage stage) {
    _timer?.cancel();
    state = (elapsed: 0, stage: stage);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = (elapsed: state.elapsed + 1, stage: state.stage);
    });
  }

  /// Cancels the timer and resets to the idle state.
  void stop() {
    _timer?.cancel();
    _timer = null;
    state = (elapsed: 0, stage: null);
  }
}

final calibrationTimerProvider =
    NotifierProvider<CalibrationTimerNotifier, CalibrationTimerState>(
  CalibrationTimerNotifier.new,
);
