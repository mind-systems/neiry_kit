import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Baseline values from the productivity classifier.
///
/// Mirrors `clCProductivity_Baselines`. Each field is `null` when the SDK has
/// not yet produced a valid reading (sentinel `-1` / `-1.0`).
@immutable
class ProductivityBaselines {
  const ProductivityBaselines({
    required this.timestamp,
    this.gravity,
    this.productivity,
    this.fatigue,
    this.reverseFatigue,
    this.relaxation,
    this.concentration,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Gravity baseline, or `null` if not yet available.
  final double? gravity;

  /// Productivity baseline, or `null` if not yet available.
  final double? productivity;

  /// Fatigue baseline, or `null` if not yet available.
  final double? fatigue;

  /// Reverse-fatigue baseline, or `null` if not yet available.
  final double? reverseFatigue;

  /// Relaxation baseline, or `null` if not yet available.
  final double? relaxation;

  /// Concentration baseline, or `null` if not yet available.
  final double? concentration;

  factory ProductivityBaselines.fromMap(Map<Object?, Object?> map) {
    return ProductivityBaselines(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      gravity: orNull(map['gravity']),
      productivity: orNull(map['productivity']),
      fatigue: orNull(map['fatigue']),
      reverseFatigue: orNull(map['reverseFatigue']),
      relaxation: orNull(map['relaxation']),
      concentration: orNull(map['concentration']),
    );
  }
}
