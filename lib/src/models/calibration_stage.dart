// Mirrors `clCIndividualNFBCalibrationStage` from `CNFBCalibrator.h`.
// Stages are 0-indexed to match the C SDK's enum layout.

/// Stage within the individual NFB calibration pipeline.
///
/// The calibration alternates between eyes-closed and eyes-open epochs:
/// - [stage1] / [stage3] — eyes closed for ~20 s
/// - [stage2] / [stage4] — eyes open for ~20 s
enum CalibrationStage {
  /// Stage 1: eyes closed (~20 s). Code 0.
  stage1(0),

  /// Stage 2: eyes open (~20 s). Code 1.
  stage2(1),

  /// Stage 3: eyes closed (~20 s). Code 2.
  stage3(2),

  /// Stage 4: eyes open (~20 s). Code 3.
  stage4(3);

  const CalibrationStage(this.code);

  /// The integer value used by the C SDK for this stage.
  final int code;

  /// Returns the [CalibrationStage] whose [code] equals [code].
  ///
  /// Throws [ArgumentError] when [code] does not correspond to any known value.
  static CalibrationStage fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    throw ArgumentError('Unknown CalibrationStage code: $code');
  }
}
