import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Index values from the productivity classifier.
///
/// Mirrors `clCProductivity_Indexes`. Float fields are `null` when the SDK has
/// not yet produced a valid reading (sentinel `-1` / `-1.0`). Integer and
/// boolean fields are always valid once received.
///
/// [relaxation] encodes `clCProductivity_RecommendationValue`:
/// 0 = NoRecommendation, 1 = Involvement, 2 = Relaxation,
/// 3 = SlightFatigue, 4 = SevereFatigue, 5 = ChronicFatigue.
///
/// [stress] encodes `clCProductivity_StressValue`:
/// 0 = NoStress, 1 = Anxiety, 2 = Stress.
@immutable
class ProductivityIndexes {
  const ProductivityIndexes({
    required this.timestamp,
    required this.relaxation,
    required this.stress,
    required this.hasArtifacts,
    this.gravityBaseline,
    this.productivityBaseline,
    this.fatigueBaseline,
    this.reverseFatigueBaseline,
    this.relaxationBaseline,
    this.concentrationBaseline,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Gravity baseline score, or `null` if not yet available.
  final double? gravityBaseline;

  /// Productivity baseline score, or `null` if not yet available.
  final double? productivityBaseline;

  /// Fatigue baseline score, or `null` if not yet available.
  final double? fatigueBaseline;

  /// Reverse-fatigue baseline score, or `null` if not yet available.
  final double? reverseFatigueBaseline;

  /// Relaxation baseline score, or `null` if not yet available.
  final double? relaxationBaseline;

  /// Concentration baseline score, or `null` if not yet available.
  final double? concentrationBaseline;

  /// Recommendation value (`clCProductivity_RecommendationValue`).
  final int relaxation;

  /// Stress level (`clCProductivity_StressValue`).
  final int stress;

  /// `true` when EEG artifacts were detected during this sample window.
  final bool hasArtifacts;

  factory ProductivityIndexes.fromMap(Map<Object?, Object?> map) {
    return ProductivityIndexes(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      relaxation: map['relaxation'] as int,
      stress: map['stress'] as int,
      hasArtifacts: map['hasArtifacts'] as bool,
      gravityBaseline: orNull(map['gravityBaseline']),
      productivityBaseline: orNull(map['productivityBaseline']),
      fatigueBaseline: orNull(map['fatigueBaseline']),
      reverseFatigueBaseline: orNull(map['reverseFatigueBaseline']),
      relaxationBaseline: orNull(map['relaxationBaseline']),
      concentrationBaseline: orNull(map['concentrationBaseline']),
    );
  }
}
