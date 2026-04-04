import 'calibration_stage.dart';
import 'individual_nfb_data.dart';

/// An event emitted by the NFB calibration EventChannel.
///
/// Use exhaustive pattern matching to handle both subtypes:
/// ```dart
/// switch (event) {
///   case CalibrationStageFinished(:final stage): ...
///   case CalibrationCompleted(:final data): ...
/// }
/// ```
sealed class CalibrationEvent {
  const CalibrationEvent();

  /// Deserializes a raw map from the `NeiryEvents.nfbCalibration` EventChannel.
  ///
  /// Dispatches by `map['type']`:
  /// - `'stage'` → [CalibrationStageFinished]
  /// - `'done'`  → [CalibrationCompleted]
  ///
  /// Throws [ArgumentError] for unknown type strings.
  static CalibrationEvent deserialize(Map<Object?, Object?> map) {
    final type = map['type'] as String;
    switch (type) {
      case 'stage':
        return CalibrationStageFinished(
          stage: CalibrationStage.fromCode(map['stage'] as int),
        );
      case 'done':
        return CalibrationCompleted(
          data: IndividualNfbData.fromMap(
            map['data'] as Map<Object?, Object?>,
          ),
        );
      default:
        throw ArgumentError('Unknown CalibrationEvent type: $type');
    }
  }
}

/// Fired when a single calibration stage finishes.
final class CalibrationStageFinished extends CalibrationEvent {
  const CalibrationStageFinished({required this.stage});

  /// The stage that just completed.
  final CalibrationStage stage;
}

/// Fired when the full calibration run completes.
final class CalibrationCompleted extends CalibrationEvent {
  const CalibrationCompleted({required this.data});

  /// The individual NFB data produced by the calibration.
  final IndividualNfbData data;
}
