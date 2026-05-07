import 'package:neiry_kit/neiry_kit.dart';

/// UI state for the calibration screen — derived from [calibrationProvider]
/// and [calibrationTimerProvider]; never stored directly in Riverpod.
sealed class CalibrationUiState {
  const CalibrationUiState();
}

/// No calibration in progress and no completed data.
final class CalibrationIdle extends CalibrationUiState {
  const CalibrationIdle();

  String get instruction => 'Press Start to begin calibration';
}

/// A calibration stage is running.
final class CalibrationStageActive extends CalibrationUiState {
  const CalibrationStageActive(this.stage, this.elapsedSeconds);

  final CalibrationStage stage;
  final int elapsedSeconds;

  String get stageLabel => 'Stage ${stage.code + 1} / 4';

  String get instruction => switch (stage) {
        CalibrationStage.stage1 ||
        CalibrationStage.stage3 =>
          'Close your eyes and relax',
        CalibrationStage.stage2 ||
        CalibrationStage.stage4 =>
          'Open your eyes, look straight ahead',
      };
}

/// Calibration completed successfully.
final class CalibrationDone extends CalibrationUiState {
  const CalibrationDone(this.data);

  final IndividualNfbData data;

  bool get isValid => data.isValid;
}

/// Calibration failed or threw an error.
final class CalibrationError extends CalibrationUiState {
  const CalibrationError(this.message);

  final String message;
}
