import 'package:flutter/foundation.dart';

import 'nfb_calibration_fail_reason.dart';

/// Result of an individual NFB calibration run.
///
/// Mirrors `clCIndividualNFBData`. All numeric fields use `double` defaults
/// that match typical mid-range alpha values. The only field that can be
/// absent is [timestamp] — the C struct sends `-1` when no timestamp is
/// available, which is represented here as `null`.
@immutable
class IndividualNfbData {
  const IndividualNfbData({
    this.timestamp,
    this.failReason = NfbCalibrationFailReason.none,
    this.individualFrequency = 10.0,
    this.individualPeakFrequency = 10.0,
    this.individualPeakFrequencyPower = 10.0,
    this.individualPeakFrequencySuppression = 2.0,
    this.individualBandwidth = 6.0,
    this.individualNormalizedPower = 0.5,
    this.lowerFrequency = 7.0,
    this.upperFrequency = 13.0,
  });

  /// When calibration completed, or `null` if the C struct sent `-1`.
  final DateTime? timestamp;

  /// Why calibration failed, or [NfbCalibrationFailReason.none] on success.
  final NfbCalibrationFailReason failReason;

  /// Detected individual alpha peak frequency, in Hz.
  final double individualFrequency;

  /// Legacy alias for [individualFrequency], in Hz.
  final double individualPeakFrequency;

  /// Power at the alpha peak frequency, in uV²/Hz.
  final double individualPeakFrequencyPower;

  /// Ratio of closed-eyes to open-eyes alpha power (suppression index).
  final double individualPeakFrequencySuppression;

  /// Width of the individual alpha band, in Hz.
  final double individualBandwidth;

  /// Normalized alpha power in the individual band (0–1).
  final double individualNormalizedPower;

  /// Lower bound of the individual alpha band, in Hz.
  final double lowerFrequency;

  /// Upper bound of the individual alpha band, in Hz.
  final double upperFrequency;

  /// Whether the calibration completed without errors.
  bool get isValid => failReason == NfbCalibrationFailReason.none;

  factory IndividualNfbData.fromMap(Map<Object?, Object?> map) {
    final tsRaw = map['ts'];
    final DateTime? ts;
    if (tsRaw == null || (tsRaw as int) < 0) {
      ts = null;
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(tsRaw);
    }

    return IndividualNfbData(
      timestamp: ts,
      failReason: NfbCalibrationFailReason.fromCode(map['failReason'] as int),
      individualFrequency: (map['individualFrequency'] as num).toDouble(),
      individualPeakFrequency:
          (map['individualPeakFrequency'] as num).toDouble(),
      individualPeakFrequencyPower:
          (map['individualPeakFrequencyPower'] as num).toDouble(),
      individualPeakFrequencySuppression:
          (map['individualPeakFrequencySuppression'] as num).toDouble(),
      individualBandwidth: (map['individualBandwidth'] as num).toDouble(),
      individualNormalizedPower:
          (map['individualNormalizedPower'] as num).toDouble(),
      lowerFrequency: (map['lowerFrequency'] as num).toDouble(),
      upperFrequency: (map['upperFrequency'] as num).toDouble(),
    );
  }

  /// Serializes this object to a map suitable for passing over MethodChannel.
  ///
  /// The timestamp is encoded as milliseconds since epoch, or `-1` when null,
  /// to round-trip cleanly with the C sentinel convention.
  Map<String, dynamic> toMap() {
    return {
      'ts': timestamp?.millisecondsSinceEpoch ?? -1,
      'failReason': failReason.code,
      'individualFrequency': individualFrequency,
      'individualPeakFrequency': individualPeakFrequency,
      'individualPeakFrequencyPower': individualPeakFrequencyPower,
      'individualPeakFrequencySuppression': individualPeakFrequencySuppression,
      'individualBandwidth': individualBandwidth,
      'individualNormalizedPower': individualNormalizedPower,
      'lowerFrequency': lowerFrequency,
      'upperFrequency': upperFrequency,
    };
  }
}
