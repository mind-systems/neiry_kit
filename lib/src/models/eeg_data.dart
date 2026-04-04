import 'package:flutter/foundation.dart';

/// Mirrors data from `clCEEGTimedData` accessor functions.
///
/// Contains raw and artifact-filtered EEG samples for all channels
/// in a single delivery batch.
@immutable
class EegData {
  const EegData({
    required this.timestamp,
    required this.rawValues,
    required this.processedValues,
    required this.channelCount,
    required this.sampleCount,
  });

  /// Timestamp of the first sample in this batch.
  final DateTime timestamp;

  /// Raw EEG samples in microvolts, indexed as `[channel][sample]`.
  final List<List<double>> rawValues;

  /// Artifact-filtered EEG samples in microvolts, indexed as `[channel][sample]`.
  ///
  /// Empty lists in Resistance mode.
  final List<List<double>> processedValues;

  /// Number of EEG channels.
  final int channelCount;

  /// Number of samples per channel in this batch.
  final int sampleCount;

  factory EegData.fromMap(Map<Object?, Object?> map) {
    List<List<double>> decodeMatrix(Object? raw) {
      return (raw as List)
          .map(
            (row) =>
                (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList();
    }

    return EegData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      rawValues: decodeMatrix(map['rawValues']),
      processedValues: decodeMatrix(map['processedValues']),
      channelCount: map['channelCount'] as int,
      sampleCount: map['sampleCount'] as int,
    );
  }
}
