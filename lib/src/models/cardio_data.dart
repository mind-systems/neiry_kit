import 'package:flutter/foundation.dart';

/// Per-sample output from the Cardio classifier.
///
/// Mirrors `clCCardio_Data`. The float metric fields are only meaningful when
/// [metricsAvailable] is `true` — when `false` they hold `0.0`.
@immutable
class CardioData {
  const CardioData({
    required this.timestamp,
    required this.heartRate,
    required this.stressIndex,
    required this.kaplanIndex,
    required this.hasArtifacts,
    required this.skinContact,
    required this.motionArtifacts,
    required this.metricsAvailable,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Heart rate in beats per minute.
  ///
  /// Only meaningful when [metricsAvailable] is `true`.
  final double heartRate;

  /// Baevsky's stress index derived from HRV analysis.
  ///
  /// Only meaningful when [metricsAvailable] is `true`.
  final double stressIndex;

  /// Kaplan index derived from HRV analysis.
  ///
  /// Only meaningful when [metricsAvailable] is `true`.
  final double kaplanIndex;

  /// `true` when any signal artifact was detected in this sample.
  final bool hasArtifacts;

  /// `true` when the PPG sensor has confirmed skin contact.
  final bool skinContact;

  /// `true` when motion artifacts are present.
  final bool motionArtifacts;

  /// `true` when the HRV-derived metrics ([heartRate], [stressIndex],
  /// [kaplanIndex]) contain valid values. When `false`, float fields hold `0.0`.
  final bool metricsAvailable;

  factory CardioData.fromMap(Map<Object?, Object?> map) {
    return CardioData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      heartRate: (map['heartRate'] as num).toDouble(),
      stressIndex: (map['stressIndex'] as num).toDouble(),
      kaplanIndex: (map['kaplanIndex'] as num).toDouble(),
      hasArtifacts: map['hasArtifacts'] as bool,
      skinContact: map['skinContact'] as bool,
      motionArtifacts: map['motionArtifacts'] as bool,
      metricsAvailable: map['metricsAvailable'] as bool,
    );
  }
}
