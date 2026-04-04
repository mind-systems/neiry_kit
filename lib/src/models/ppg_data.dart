import 'package:flutter/foundation.dart';

/// A batch of raw PPG waveform samples from `clCPPGTimedData`.
///
/// The native bridge iterates `clCPPGTimedData_GetCount`, `_GetValue`, and
/// `_GetTimestampMilli` to build this batch before sending it over the
/// EventChannel.
@immutable
class PpgData {
  const PpgData({
    required this.values,
    required this.timestamps,
    required this.sampleCount,
  });

  /// PPG sample values for this batch.
  final List<double> values;

  /// Per-sample timestamps in milliseconds since epoch.
  final List<int> timestamps;

  /// Number of samples in this batch.
  final int sampleCount;

  factory PpgData.fromMap(Map<Object?, Object?> map) {
    return PpgData(
      values: (map['values'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      timestamps: (map['timestamps'] as List)
          .map((v) => (v as num).toInt())
          .toList(),
      sampleCount: map['sampleCount'] as int,
    );
  }
}
