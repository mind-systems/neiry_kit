import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Per-sample output from the productivity classifier.
///
/// Mirrors `clCProductivity_Metrics`. Float fields are `null` when the SDK has
/// not yet produced a valid reading (sentinel `-1` / `-1.0`). [fatigueGrowthRate]
/// is always valid once received. [artifactsData] is `null` when the native
/// bridge sends no artifact bytes (`artifactsSize == 0`).
///
/// [fatigueGrowthRate] encodes `clCProductivity_FatigueGrowthRate`:
/// 0 = None, 1 = Low, 2 = Medium, 3 = High.
@immutable
class ProductivityMetrics {
  const ProductivityMetrics({
    required this.timestamp,
    required this.fatigueGrowthRate,
    this.fatigueScore,
    this.reverseFatigueScore,
    this.gravityScore,
    this.relaxationScore,
    this.concentrationScore,
    this.productivityScore,
    this.currentValue,
    this.alpha,
    this.productivityBaseline,
    this.accumulatedFatigue,
    this.artifactsData,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Fatigue score (0–1 normalized), or `null` if not yet available.
  final double? fatigueScore;

  /// Reverse-fatigue score (0–1 normalized), or `null` if not yet available.
  final double? reverseFatigueScore;

  /// Gravity score (0–1 normalized), or `null` if not yet available.
  final double? gravityScore;

  /// Relaxation score (0–1 normalized), or `null` if not yet available.
  final double? relaxationScore;

  /// Concentration score (0–1 normalized), or `null` if not yet available.
  final double? concentrationScore;

  /// Productivity score (0–1 normalized), or `null` if not yet available.
  final double? productivityScore;

  /// Current productivity value (0–1 normalized), or `null` if not yet available.
  final double? currentValue;

  /// Alpha band contribution (0–1 normalized), or `null` if not yet available.
  final double? alpha;

  /// Productivity baseline, or `null` if not yet available.
  final double? productivityBaseline;

  /// Accumulated fatigue, or `null` if not yet available.
  final double? accumulatedFatigue;

  /// Fatigue growth rate (`clCProductivity_FatigueGrowthRate`).
  final int fatigueGrowthRate;

  /// Raw artifact bytes, or `null` when no artifact data was sent by the bridge.
  final Uint8List? artifactsData;

  factory ProductivityMetrics.fromMap(Map<Object?, Object?> map) {
    return ProductivityMetrics(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      fatigueGrowthRate: map['fatigueGrowthRate'] as int,
      fatigueScore: orNull(map['fatigueScore']),
      reverseFatigueScore: orNull(map['reverseFatigueScore']),
      gravityScore: orNull(map['gravityScore']),
      relaxationScore: orNull(map['relaxationScore']),
      concentrationScore: orNull(map['concentrationScore']),
      productivityScore: orNull(map['productivityScore']),
      currentValue: orNull(map['currentValue']),
      alpha: orNull(map['alpha']),
      productivityBaseline: orNull(map['productivityBaseline']),
      accumulatedFatigue: orNull(map['accumulatedFatigue']),
      artifactsData: map['artifactsData'] == null
          ? null
          : map['artifactsData'] as Uint8List,
    );
  }
}
