import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Mirrors data from `clCPSDData` accessor functions.
///
/// Contains power spectral density values for all channels and frequency bins,
/// along with band boundary definitions.
@immutable
class PsdData {
  const PsdData({
    required this.timestamp,
    required this.values,
    required this.frequencies,
    required this.channelCount,
    required this.frequencyCount,
    required this.deltaLower,
    required this.deltaUpper,
    required this.thetaLower,
    required this.thetaUpper,
    required this.alphaLower,
    required this.alphaUpper,
    required this.smrLower,
    required this.smrUpper,
    required this.betaLower,
    required this.betaUpper,
    this.individualAlphaLower,
    this.individualAlphaUpper,
    this.individualBetaLower,
    this.individualBetaUpper,
  });

  /// Timestamp of this PSD frame.
  final DateTime timestamp;

  /// PSD power values, indexed as `[channel][frequencyBin]`.
  final List<List<double>> values;

  /// Frequency bin centers in Hz, length equals [frequencyCount].
  final List<double> frequencies;

  /// Number of EEG channels.
  final int channelCount;

  /// Number of frequency bins.
  final int frequencyCount;

  final double deltaLower;
  final double deltaUpper;
  final double thetaLower;
  final double thetaUpper;
  final double alphaLower;
  final double alphaUpper;
  final double smrLower;
  final double smrUpper;
  final double betaLower;
  final double betaUpper;

  /// Individual alpha lower bound, or `null` if not yet calibrated.
  final double? individualAlphaLower;

  /// Individual alpha upper bound, or `null` if not yet calibrated.
  final double? individualAlphaUpper;

  /// Individual beta lower bound, or `null` if not yet calibrated.
  final double? individualBetaLower;

  /// Individual beta upper bound, or `null` if not yet calibrated.
  final double? individualBetaUpper;

  factory PsdData.fromMap(Map<Object?, Object?> map) {
    List<List<double>> decodeMatrix(Object? raw) {
      return (raw as List)
          .map(
            (row) =>
                (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList();
    }

    List<double> decodeDoubles(Object? raw) {
      return (raw as List).map((v) => (v as num).toDouble()).toList();
    }

    return PsdData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      values: decodeMatrix(map['values']),
      frequencies: decodeDoubles(map['frequencies']),
      channelCount: map['channelCount'] as int,
      frequencyCount: map['frequencyCount'] as int,
      deltaLower: (map['deltaLower'] as num).toDouble(),
      deltaUpper: (map['deltaUpper'] as num).toDouble(),
      thetaLower: (map['thetaLower'] as num).toDouble(),
      thetaUpper: (map['thetaUpper'] as num).toDouble(),
      alphaLower: (map['alphaLower'] as num).toDouble(),
      alphaUpper: (map['alphaUpper'] as num).toDouble(),
      smrLower: (map['smrLower'] as num).toDouble(),
      smrUpper: (map['smrUpper'] as num).toDouble(),
      betaLower: (map['betaLower'] as num).toDouble(),
      betaUpper: (map['betaUpper'] as num).toDouble(),
      individualAlphaLower: orNull(map['individualAlphaLower']),
      individualAlphaUpper: orNull(map['individualAlphaUpper']),
      individualBetaLower: orNull(map['individualBetaLower']),
      individualBetaUpper: orNull(map['individualBetaUpper']),
    );
  }
}
