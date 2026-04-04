import 'package:flutter/foundation.dart';

/// Mirrors data from `clCEEGArtifacts` accessor functions.
///
/// Contains per-channel artifact flags and signal quality metrics.
@immutable
class EegArtifactData {
  const EegArtifactData({
    required this.timestamp,
    required this.artifacts,
    required this.qualities,
    required this.channelCount,
  });

  /// Timestamp of this artifact snapshot.
  final DateTime timestamp;

  /// Per-channel artifact flag byte (uint8), one entry per channel.
  final List<int> artifacts;

  /// Per-channel EEG signal quality (float), one entry per channel.
  final List<double> qualities;

  /// Number of EEG channels.
  final int channelCount;

  factory EegArtifactData.fromMap(Map<Object?, Object?> map) {
    return EegArtifactData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      artifacts: (map['artifacts'] as List).map((v) => v as int).toList(),
      qualities: (map['qualities'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      channelCount: map['channelCount'] as int,
    );
  }
}
