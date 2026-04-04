// Mirrors `clCIndividualNFBCalibrationFailReason` from `CNFBCalibrator.h`.
// The `Nfb` prefix distinguishes this from physio/productivity calibration,
// which have separate failure modes not covered here.

/// Reason why the individual NFB calibration failed (or succeeded).
enum NfbCalibrationFailReason {
  /// Calibration succeeded — no failure. Code 0.
  none(0),

  /// Too many EEG artifacts were detected during the session. Code 1.
  tooManyArtifacts(1),

  /// The detected alpha peak frequency is at the band border. Code 2.
  peakFrequencyAtBorder(2);

  const NfbCalibrationFailReason(this.code);

  /// The integer value used by the C SDK for this reason.
  final int code;

  /// Returns the [NfbCalibrationFailReason] whose [code] equals [code].
  ///
  /// Throws [ArgumentError] when [code] does not correspond to any known value.
  static NfbCalibrationFailReason fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    throw ArgumentError('Unknown NfbCalibrationFailReason code: $code');
  }
}
